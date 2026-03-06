import { and, desc, eq } from 'drizzle-orm'
import type { AgenticServer } from 'main'
import { AgenticDB } from 'src/database/AgenticDB'
import { sessions, SessionStatus, type Session } from 'src/database/schemas'
import type { ASMState } from 'src/state/IASMState'
import { BaseManager } from './BaseManager'
import type { SessionEvents } from 'src/data/events'
import { MessageManager } from './MessageManager'
import { SessionSummaryManager } from './SessionSummaryManager'

export class SessionManager extends BaseManager<SessionEvents> {
  private db: ReturnType<AgenticDB['getDB']>
  private sessions: Map<string, ASMState['session']> = new Map()
  private connection: ASMState['connection'] | null = null
  private activeSessionId: string | null = null

  private messageManager: MessageManager
  private sessionSummaryManager: SessionSummaryManager

  constructor(private readonly server_instance: AgenticServer) {
    super()
    const dbInstance = AgenticDB.getInstance()
    this.db = dbInstance.getDB()

    this.messageManager = new MessageManager()
    this.sessionSummaryManager = new SessionSummaryManager(this.messageManager)
  }

  async init() {
    const currentAgent = this.server_instance.getState().agent

    if (!currentAgent) {
      this.emit('session.error', 'No active agent found in state')
      return
    }

    const availableSessions = await this.db
      .select()
      .from(sessions)
      .where(eq(sessions.agent_id, currentAgent.id))
      .orderBy(desc(sessions.created_at))

    availableSessions.forEach((session) => {
      this.sessions.set(session.id, session)
    })

    const connection = this.server_instance.getState()?.connection

    if (!connection) {
      this.emit(
        'session.error',
        'No active connection found. Please use `client/init` command first.',
      )
      return
    }

    this.connection = connection
  }

  async createNewSession(name?: string) {
    const currentAgent = this.server_instance.getState().agent

    if (!currentAgent) {
      this.emit('session.error', 'No active agent found in state')
      return
    }

    if (!this.connection) {
      this.emit(
        'session.error',
        'No active connection found. Please use `client/init` command first.',
      )
      return
    }

    if (this.activeSessionId) {
      await this.closeCurrentSession()
    }

    const newSession = await this.connection.csc.newSession({
      cwd: currentAgent.cwd,
      mcpServers: [],
    })

    this.emit('session.acp_created', newSession)

    const sessionRecord: Session['Insert'] = {
      agent_id: currentAgent.id,
      acp_session_id: newSession.sessionId,
      name: name || `Session ${this.sessions.size + 1}`,
    }

    const insertedSession = await this.db
      .insert(sessions)
      .values(sessionRecord)
      .returning()
      .then((res) => res[0])

    if (!insertedSession) {
      this.emit('session.error', 'Failed to insert new session into database')
      return
    }

    this.sessions.set(insertedSession.id, insertedSession)
    this.activeSessionId = insertedSession.id

    this.emit('session.created', insertedSession)
    this.emit('session.loaded', insertedSession)
  }

  async closeCurrentSession() {
    if (!this.activeSessionId) {
      this.emit('session.error', 'No active session to close')
      return
    }

    //TODO: do this in a separate thread or process so we don't block the main event loop while summarizing
    await this.sessionSummaryManager.createSummary(this.activeSessionId)
    this.updateSession('summary_generated', true)

    this.updateSession('status', SessionStatus.completed)
    this.emit(
      'session.completed',
      this.sessions.get(this.activeSessionId) ?? undefined,
    )
    this.activeSessionId = null
  }

  updateSession<T extends keyof Session['Update']>(
    field: T,
    value: Session['Update'][T],
    id?: string,
  ) {
    const sessionId = id || this.activeSessionId

    if (!sessionId) {
      this.emit('session.error', 'No active session ID found to update')
      return
    }

    const session = this.sessions.get(sessionId)

    if (!session) {
      this.emit('session.error', `Session with ID ${sessionId} not found`)
      return
    }

    const updatedSession = { ...session, [field]: value }

    this.db
      ?.update(sessions)
      .set({ [field]: value })
      .where(and(eq(sessions.id, sessionId)))

    this.sessions.set(sessionId, updatedSession)
    this.emit('session.updated', updatedSession)
  }

  renameSession(newName: string, id?: string) {
    this.updateSession('name', newName, id)
  }

  deleteSession(id: string) {
    const session = this.sessions.get(id)

    if (!session) {
      this.emit('session.error', `Session with ID ${id} not found`)
      return
    }

    this.db?.delete(sessions).where(eq(sessions.id, id))

    this.sessions.delete(id)
    this.emit('session.deleted', id)
  }

  launchSession(id?: string) {}

  dispose() {
    this.sessions.clear()
    this.activeSessionId = null
    this.connection = null
  }
}
