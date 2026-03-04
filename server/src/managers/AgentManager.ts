import {
  ClientSideConnection,
  ndJsonStream,
  type Agent as AcpAgent,
  PROTOCOL_VERSION,
} from '@agentclientprotocol/sdk'
import { and, desc, eq } from 'drizzle-orm'
import type { AgenticServer } from 'main'
import EventEmitter from 'node:events'
import { AcpClient } from 'src/acp/Client'
import { FileSystemHandler } from 'src/acp/handlers/FileSystemHandler'
import { PermissionHandler } from 'src/acp/handlers/PermissionHandler'
import { TerminalHandler } from 'src/acp/handlers/TerminalHandler'
import { AgentEventNames } from 'src/data/events'
import { Providers, PROVIDERS } from 'src/data/providers'
import { AgenticDB } from 'src/database/AgenticDB'
import { agents, type Agent } from 'src/database/schemas'
import type { ASMPayloadParams } from 'src/openrpc/schemas'
import type { ASMState } from 'src/state/IASMState'
import { tapStream } from 'src/utils/helpers'
import { logDebug, logError } from 'src/utils/logger'
import { spawnShellCommand } from 'src/utils/shell'

export class AgentManager extends EventEmitter {
  private db: ReturnType<AgenticDB['getDB']> | null = null
  private agent: ASMState['agent'] | null = null

  private fileSystemHandler: FileSystemHandler
  private permissionHandler: PermissionHandler
  private terminalHandler: TerminalHandler

  constructor(
    private provider: Providers,
    private cwd: string,
    private readonly server_instance: AgenticServer,
  ) {
    super()

    const dbInstance = AgenticDB.getInstance()
    this.db = dbInstance.getDB()

    this.fileSystemHandler = new FileSystemHandler()
    this.permissionHandler = new PermissionHandler(this.server_instance)
    this.terminalHandler = new TerminalHandler(this.server_instance)
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

    // const process = this.agent.process

    // ;(async () => {
    //   if (!process.stdout || typeof process.stdout === 'number') {
    //     logError(`No stdout stream for agent ${this.agent?.id}`)
    //     return
    //   }
    //   const decoder = new TextDecoder()
    //   let buffer = ''

    //   try {
    //     for await (const chunk of process.stdout) {
    //       buffer += decoder.decode(chunk)

    //       const lines = buffer.split('\n')
    //       buffer = lines.pop()! // keep any incomplete trailing line

    //       for (const line of lines) {
    //         if (!line.trim()) continue
    //         this.emit(AgentEventNames.message, line)
    //       }
    //     }
    //   } catch (err) {
    //     logDebug(`Agent stdout stream closed for agent ${this.agent?.id}:`, err)
    //   }
    // })()

    // ;(async () => {
    //   if (!process.stderr || typeof process.stderr === 'number') {
    //     logError(`No stderr stream for agent ${this.agent?.id}`)
    //     return
    //   }
    //   const decoder = new TextDecoder()
    //   let buffer = ''

    //   try {
    //     for await (const chunk of process.stderr) {
    //       buffer += decoder.decode(chunk)

    //       const lines = buffer.split('\n')
    //       buffer = lines.pop()! // keep any incomplete trailing line

    //       for (const line of lines) {
    //         if (!line.trim()) continue
    //         this.emit(AgentEventNames.message, line)
    //       }
    //     }
    //   } catch (err) {
    //     logDebug(`Agent stdout stream closed for agent ${this.agent?.id}:`, err)
    //   }
    // })()
  }

  public async connect() {
    if (!this.agent) {
      throw new Error('Agent is not initialized')
    }

    if (!this.agent.process) {
      throw new Error('Agent process is not running')
    }

    logDebug(`Connecting to agent ${this.agent.id}`)

    const { stdin, stdout } = this.agent.process
    if (
      !stdout ||
      typeof stdout === 'number' ||
      !stdin ||
      typeof stdin === 'number'
    ) {
      throw new Error(
        `Agent process for agent ${this.agent.id} does not have valid stdio streams`,
      )
    }

    // FileSink → WritableStream<Uint8Array> adapter
    const writableStdin = new WritableStream<Uint8Array>({
      write(chunk) {
        stdin.write(chunk)
      },
      close() {
        stdin.end()
      },
      abort() {
        stdin.end()
      },
    })

    const stream = ndJsonStream(writableStdin, stdout)
    const tappedStream = tapStream(stream)

    const client = new AcpClient(
      this.fileSystemHandler,
      this.permissionHandler,
      this.terminalHandler,
    )

    const connection = new ClientSideConnection((agent: AcpAgent) => {
      client.setAgent(agent)
      return client
    }, tappedStream)

    //Initialize the connection
    const initResponse = await connection.initialize({
      protocolVersion: PROTOCOL_VERSION,
      clientInfo: {
        name: 'Neovim Agentic Client',
        version: '0.1',
      },
      clientCapabilities: {
        fs: {
          readTextFile: true,
          writeTextFile: true,
        },
        terminal: true,
      },
    })

    logDebug(`Connection initialized with response:`, initResponse)
    return { connection, client, initResponse }
  }

  public handleTerminalResponse(msg: ASMPayloadParams['client/terminal']) {
    this.terminalHandler.handleResponse(msg)
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
    if (this.permissionHandler) {
      this.permissionHandler.dispose()
    }

    if (this.terminalHandler) {
      this.terminalHandler.dispose()
    }

    if (this.fileSystemHandler) {
      this.fileSystemHandler.dispose()
    }

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
