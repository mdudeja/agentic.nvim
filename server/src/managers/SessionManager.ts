import { and, desc, eq } from 'drizzle-orm'
import type { AgenticServer } from 'main'
import { AgenticDB } from 'src/database/AgenticDB'
import { sessions, SessionStatus, type Session } from 'src/database/schemas'
import type { ASMState } from 'src/state/IASMState'
import { BaseManager } from './BaseManager'
import type { SessionEvents } from 'src/data/events'
import {
  ClientSideConnection,
  RequestError,
  type ContentBlock,
  type LoadSessionResponse,
} from '@agentclientprotocol/sdk'

export class SessionManager extends BaseManager<SessionEvents> {
  private db: ReturnType<AgenticDB['getDB']>
  private sessions: Map<string, ASMState['session']> = new Map()
  private connection: ASMState['connection'] | null = null
  private activeSessionId: string | null = null

  private authenticationAttempted: boolean = false

  constructor(private readonly server_instance: AgenticServer) {
    super()
    const dbInstance = AgenticDB.getInstance()
    this.db = dbInstance.getDB()
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

    if (this.activeSessionId) {
      await this.closeCurrentSession()
    }

    const newSession = await this._createAcpSession(currentAgent)

    if (!newSession) {
      this.emit('session.error', 'Failed to create new session')
      return
    }

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

    this.sessions.set(insertedSession.id, {
      ...insertedSession,
      configOptions: newSession.configOptions ?? undefined,
      models: newSession.models ?? undefined,
      modes: newSession.modes ?? undefined,
    })
    this.activeSessionId = insertedSession.id

    this.emit('session.created', this.sessions.get(this.activeSessionId))
    this.emit('session.loaded', this.sessions.get(this.activeSessionId))
  }

  async closeCurrentSession() {
    if (!this.activeSessionId) {
      this.emit('session.error', 'No active session to close')
      return
    }

    await this.updateSession('status', SessionStatus.completed)
    this.emit(
      'session.completed',
      this.sessions.get(this.activeSessionId) ?? undefined,
    )
    this.activeSessionId = null
  }

  async updateSession<T extends keyof Session['Update']>(
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

    await this.db
      .update(sessions)
      .set({ [field]: value })
      .where(and(eq(sessions.id, sessionId)))

    this.sessions.set(sessionId, updatedSession)
    this.emit('session.updated', updatedSession)
  }

  async renameSession(newName: string, id?: string) {
    await this.updateSession('name', newName, id)
  }

  async deleteSession(id: string) {
    const session = this.sessions.get(id)

    if (!session) {
      this.emit('session.error', `Session with ID ${id} not found`)
      return
    }

    await this.db.delete(sessions).where(eq(sessions.id, id))

    this.sessions.delete(id)
    this.emit('session.deleted', id)
  }

  async archiveSession(id: string) {
    const session = this.sessions.get(id)

    if (!session) {
      this.emit('session.error', `Session with ID ${id} not found`)
      return
    }

    await this.updateSession('is_archived', true, id)
  }

  async unarchiveSession(id: string) {
    const session = this.sessions.get(id)

    if (!session) {
      this.emit('session.error', `Session with ID ${id} not found`)
      return
    }

    await this.updateSession('is_archived', false, id)
  }

  async loadSession(id: string) {
    const session = this.sessions.get(id)

    if (!session) {
      this.emit('session.error', `Session with ID ${id} not found`)
      return
    }

    const currentAgent = this.server_instance.getState().agent

    if (!currentAgent) {
      this.emit('session.error', 'No active agent found in state')
      return
    }

    if (this.activeSessionId) {
      await this.closeCurrentSession()
    }

    let loaded: LoadSessionResponse | null = null
    const capabilities = this.connection!.initResponse.agentCapabilities

    if (capabilities?.loadSession) {
      loaded = await this.connection!.csc.loadSession({
        cwd: currentAgent.cwd,
        mcpServers: [],
        sessionId: session.acp_session_id,
      })
    } else {
      const newSession = await this.createNewSession(session.name ?? undefined)
    }

    this.activeSessionId = id
    await this.updateSession('status', SessionStatus.active, id)

    this.sessions.set(id, {
      ...session,
      configOptions: loaded.configOptions ?? session.configOptions,
      models: loaded.models ?? session.models,
      modes: loaded.modes ?? session.modes,
    })

    this.emit('session.loaded', this.sessions.get(id))
  }

  forkSession(id?: string) {}

  resumeSession(id?: string) {}

  setSessionMode(modeId: string, id?: string) {}

  setSessionModel(modelId: string, id?: string) {}

  setSessionConfigOption(optionId: string, value: any, id?: string) {}

  prompt(prompt: ContentBlock[], id?: string) {}

  cancelTurn(id?: string) {}

  dispose() {
    this.sessions.clear()
    this.activeSessionId = null
    this.connection = null
  }

  private async _authenticate() {
    if (!this.connection) {
      this.emit(
        'session.error',
        'No active connection found. Please use `client/init` command first.',
      )
      return
    }

    const authMethods = await this.connection.initResponse.authMethods

    if (!authMethods || authMethods.length === 0) {
      this.emit(
        'session.error',
        'No authentication methods available from the server.',
      )
      return
    }

    let selectedMethod = authMethods[0]

    if (authMethods.length > 1) {
      const options = authMethods.map((method) => ({
        label: method.name,
        description: method.description,
        value: method,
      }))

      const userResponse = await this.server_instance
        .getCommsInterface()
        .question({
          questionId: 'select_auth_method',
          question: `Multiple authentication methods are available. Please select one:
        ${options.map((option, index) => `${index + 1}. ${option.label} - ${option.description}`).join('\n')}
        `,
        })

      const selectedIndex = parseInt(userResponse) - 1

      if (
        isNaN(selectedIndex) ||
        selectedIndex < 0 ||
        selectedIndex >= options.length
      ) {
        this.emit(
          'session.error',
          'Invalid selection for authentication method.',
        )
        return
      }

      selectedMethod = options[selectedIndex]?.value
    }

    if (!selectedMethod) {
      this.emit('session.error', 'No authentication method selected.')
      return
    }

    try {
      await this.connection.csc.authenticate({ methodId: selectedMethod.id })
      this.authenticationAttempted = true
    } catch (error) {
      this.emit('session.error', `Authentication failed: ${error}`)
      return
    }
  }

  private async _createAcpSession(currentAgent: ASMState['agent']) {
    if (!this.connection) {
      this.emit(
        'session.error',
        'No active connection found. Please use `client/init` command first.',
      )
      return
    }

    if (this.authenticationAttempted) {
      this.emit(
        'session.error',
        'Session creation failed after authentication attempt. Please check your credentials and try again.',
      )
      return
    }

    try {
      const newSession = await this.connection.csc.newSession({
        cwd: currentAgent!.cwd,
        mcpServers: [],
      })
      this.emit('session.acp_created', newSession)
      return newSession
    } catch (error) {
      const errorIsAuthError =
        (error instanceof RequestError && error.code === -32000) ||
        (error as any)?.code === -32000 ||
        (error as any)?.message?.toLowerCase().includes('auth')

      if (!errorIsAuthError) {
        this.emit('session.error', `Failed to create new session: ${error}`)
        this.server_instance.dispose()
        return
      }

      await this._authenticate()
      await this._createAcpSession(currentAgent)
    }
  }
}
