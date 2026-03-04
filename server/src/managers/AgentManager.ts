import { and, desc, eq } from 'drizzle-orm'
import EventEmitter from 'node:events'
import { AgentEventNames } from 'src/data/events'
import { Providers, PROVIDERS } from 'src/data/providers'
import { AgenticDB } from 'src/database/AgenticDB'
import { agents, type Agent } from 'src/database/schemas'
import type { ASMState } from 'src/state/IASMState'
import { logDebug, logError } from 'src/utils/logger'
import { spawnShellCommand } from 'src/utils/shell'

export class AgentManager extends EventEmitter {
  private db: typeof AgenticDB.prototype.db
  private agent: ASMState['agent'] | null = null

  constructor(
    private provider: Providers,
    private cwd: string,
  ) {
    super()

    const dbInstance = AgenticDB.getInstance()
    this.db = dbInstance.getDB()
  }

  public async init() {
    if (!this.db) {
      throw new Error('Database is not initialized')
    }

    const existingAgent = await this.db
      .select()
      .from(agents)
      .where(
        and(eq(agents.provider_name, this.provider), eq(agents.cwd, this.cwd)),
      )
      .orderBy(desc(agents.created_at))
      .limit(1)
      .then((res) => res[0] || null)

    if (!existingAgent) {
      const agent = await this._createNew()
      if (!agent) {
        throw new Error('Failed to create new agent')
      }

      this.agent = agent

      this.emit(AgentEventNames.created, agent)
      this.emit(AgentEventNames.loaded, agent)
      return
    }

    this.agent = existingAgent
    this.emit(AgentEventNames.loaded, existingAgent)
  }

  public spawn() {
    if (!this.agent) {
      throw new Error('Agent is not initialized')
    }

    if (this.agent.process) {
      return
    }

    this.agent.process = spawnShellCommand({
      command: this.agent.provider_command,
      args: this.agent.provider_args,
      cwd: this.agent.cwd,
      env: this.agent.env || undefined,
    })

    this.emit(AgentEventNames.spawned, this.agent)
  }

  public kill() {
    if (!this.agent || !this.agent.process) {
      return
    }

    logDebug(`Killing process for agent ${this.agent.id}`)

    try {
      this.agent.process.kill('SIGKILL')
      this.agent.process = undefined
      this.emit(AgentEventNames.killed, this.agent)
    } catch (error) {
      logError(`Failed to kill process for agent ${this.agent.id}:`, error)
    }
  }

  dispose() {
    this.removeAllListeners()
    this.kill()
    this.agent = null
  }

  public override emit(event: AgentEventNames, payload?: ASMState['agent']) {
    return super.emit(event, payload)
  }

  public override on(
    event: AgentEventNames,
    listener: (payload?: ASMState['agent']) => void,
  ) {
    return super.on(event, listener)
  }

  private async _createNew() {
    const pConfig = PROVIDERS[this.provider]

    if (!pConfig) {
      throw new Error(`Unsupported provider: ${this.provider}`)
    }

    const newAgent: Agent['Insert'] = {
      provider_name: this.provider,
      cwd: this.cwd,
      provider_title: pConfig.name,
      provider_command: pConfig.command,
      provider_args: pConfig.args as unknown as string[],
    }

    const created = await this.db?.insert(agents).values(newAgent).returning()
    return created && created.length && created[0]
  }
}
