import type { Subprocess } from 'bun'
import { and, desc, eq } from 'drizzle-orm'
import EventEmitter from 'node:events'
import { AgentEventNames } from 'src/data/events'
import { PROVIDERS } from 'src/data/providers'
import { AgenticDB } from 'src/database/AgenticDB'
import { agents, type Agent } from 'src/database/schemas'
import type { ASMState } from 'src/state'
import { spawnShellCommand } from 'src/utils/shellUtils'

export class AgentManager extends EventEmitter {
  private db: typeof AgenticDB.prototype.db
  private agents: Map<string, ASMState['agent']> = new Map()
  private active_process: Subprocess | null = null

  constructor({
    provider,
    cwd,
  }: {
    provider: ASMState['agent']['provider_name']
    cwd: ASMState['agent']['cwd']
  }) {
    super()

    const dbInstance = AgenticDB.getInstance()
    this.db = dbInstance.getDB()

    const existing = this.db
      .select()
      .from(agents)
      .where(and(eq(agents.provider_name, provider), eq(agents.cwd, cwd)))
      .orderBy(desc(agents.created_at))
      .all()

    if (!existing.length) {
      this._createNew(provider, cwd).then((agents) => {
        if (!agents || !agents.length) {
          return
        }

        for (const agent of agents) {
          this.agents.set(agent.provider_name, agent)
        }

        this.emit(AgentEventNames.created, agents)
        this.emit(AgentEventNames.loaded, agents)
      })
      return
    }

    for (const agent of existing) {
      this.agents.set(agent.provider_name, agent)
    }
    this.emit(AgentEventNames.loaded, existing)
  }

  public override emit(event: AgentEventNames, payload: ASMState['agent'][]) {
    return super.emit(event, payload)
  }

  public spawn(provider: ASMState['agent']['provider_name']) {
    if (!this.agents.size) {
      throw new Error('No agents available to spawn')
    }

    const target = this.agents.get(provider)

    if (!target) {
      throw new Error(`No agent found for provider: ${provider}`)
    }

    this.active_process = spawnShellCommand({
      command: target.provider_command,
      args: target.provider_args,
      cwd: target.cwd,
      env: target.env || undefined,
    })

    this.agents.set(provider, {
      ...target,
      process: this.active_process,
    })

    this.emit(AgentEventNames.spawned, [target])
  }

  private async _createNew(
    provider: ASMState['agent']['provider_name'],
    cwd: ASMState['agent']['cwd'],
  ) {
    const pConfig = PROVIDERS[provider]

    if (!pConfig) {
      throw new Error(`Unsupported provider: ${provider}`)
    }

    const newAgent: Agent['Insert'] = {
      provider_name: provider,
      cwd,
      provider_title: pConfig.name,
      provider_command: pConfig.command,
      provider_args: pConfig.args as unknown as string[],
    }

    const created = await this.db?.insert(agents).values(newAgent).returning()
    return created
  }
}
