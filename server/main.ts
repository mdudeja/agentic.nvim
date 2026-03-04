import { AgentManager } from 'src/managers/AgentManager'
import { Providers } from 'src/data/providers'
import { resolvePath } from 'src/utils/paths'
import { AgentEventNames } from 'src/data/events'
import { logDebug, logError, logInfo, logWarning } from 'src/utils/logger'
import { generateCatchblock } from 'src/utils/helpers'
import type {
  ASMPayload,
  ASMPayloadParams,
  ICommsInterface,
} from 'src/comms/ICommsInterface'
import { ASMPayloadSchema } from 'src/openrpc/schemas'
import { Check, Errors } from 'typebox/value'
import { ReadlineCommsInterface } from 'src/comms/ReadlineCommsInterface'
import { WebsocketCommsInterface } from 'src/comms/WebsocketCommsInterface'
import { TerminalHandler } from 'src/acp/handlers/TerminalHandler'
import { PermissionHandler } from 'src/acp/handlers/PermissionHandler'
import { FileSystemHandler } from 'src/acp/handlers/FileSystemHandler'
import { ASMStateManager } from 'src/state'

export class AgenticServer {
  static instance: AgenticServer | null = null
  private stateManager: ASMStateManager | null = null
  private commsInterface: ICommsInterface | null = null
  private agentManager: AgentManager | null = null

  private fileSystemHandler: FileSystemHandler | null = null
  private permissionHandler: PermissionHandler | null = null
  private terminalHandler: TerminalHandler | null = null

  static getInstance() {
    if (!AgenticServer.instance) {
      AgenticServer.instance = new AgenticServer()
    }
    return AgenticServer.instance
  }

  /**
   * RPC mode (default): listen for JSON-RPC payloads on stdin and respond on stdout.
   */
  async init(config: { mode: 'rpc' | 'server'; port?: number }) {
    logInfo(`Starting Agentic Server in ${config.mode.toUpperCase()} mode...`)
    try {
      this.stateManager = new ASMStateManager()
      this._initCommsInterface(config)

      this.fileSystemHandler = new FileSystemHandler()
      this.permissionHandler = new PermissionHandler(this)
      this.terminalHandler = new TerminalHandler(this)

      logWarning('Server setup complete. Awaiting commands...')
    } catch (err) {
      generateCatchblock(
        this.commsInterface,
        err,
        'Failed to initialize Agentic Server',
      )
    }
  }

  getCommsInterface() {
    return this.commsInterface
  }

  getState() {
    return this.stateManager?.getState()
  }

  dispose() {
    if (!AgenticServer.instance) {
      logInfo('AgenticServer instance already disposed.')
      return
    }

    if (this.permissionHandler) {
      this.permissionHandler.dispose()
    }

    if (this.terminalHandler) {
      this.terminalHandler.dispose()
    }

    if (this.fileSystemHandler) {
      this.fileSystemHandler.dispose()
    }

    if (this.stateManager) {
      this.stateManager.dispose()
    }

    if (this.agentManager) {
      this.agentManager.dispose()
    }

    if (this.commsInterface) {
      this.commsInterface.dispose()
    }

    AgenticServer.instance = null
    process.exit(0)
  }

  private _initCommsInterface(config: {
    mode: 'rpc' | 'server'
    port?: number
  }) {
    this.commsInterface =
      config.mode === 'rpc'
        ? new ReadlineCommsInterface()
        : new WebsocketCommsInterface()

    this.commsInterface.onMessage(async (message: string) => {
      try {
        const raw: unknown = JSON.parse(message)

        if (!Check(ASMPayloadSchema, raw)) {
          const errs = [...Errors(ASMPayloadSchema, raw)]
            .map((e) => `  ${e.instancePath || '/'}: ${e.message}`)
            .join('\n')
          throw new Error(`Invalid payload:\n${errs}`)
        }
        await this._process_payload(raw)
      } catch (err) {
        generateCatchblock(
          this.commsInterface!,
          err,
          'Failed to process incoming message',
        )
      }
    })

    this.commsInterface.onClose(() => {
      logInfo('Comms interface closed. Shutting down server...')
      this.dispose()
    })

    this.commsInterface.init()
  }

  private _initAgentManager(params: ASMPayloadParams['client/init']) {
    const resolvedCwd = resolvePath(params.cwd)
    const providerId = params.provider || 'copilot'

    logDebug(
      `Initializing agent with provider ${providerId} in directory ${resolvedCwd}`,
    )

    if (!this.agentManager) {
      this.agentManager = new AgentManager(Providers[providerId], resolvedCwd)
    }

    this.agentManager.on(AgentEventNames.loaded, (agent) => {
      if (!agent) {
        logError('Loaded event received without agent data')
        const err = new Error('Failed to load agent')
        this.commsInterface?.respond({
          id: null,
          error: err,
        })
        return
      }

      logDebug(`Agent loaded with ID ${agent.id}`)
      this.stateManager?.setItem('agent', agent)

      this.agentManager?.spawn()
    })

    this.agentManager.on(AgentEventNames.spawned, (agent) => {
      if (!agent) {
        logError('Spawned event received without agent data')
        const err = new Error('Failed to spawn agent')
        this.commsInterface?.respond({
          id: null,
          error: err,
        })
        return
      }

      logDebug(`Agent spawned with ID ${agent.id}`)
      this.stateManager?.setItem('agent', agent)
      this.commsInterface?.respond({
        id: null,
        result: { success: true, agentId: agent.id },
      })
    })

    this.agentManager.on(AgentEventNames.killed, (agent) => {
      if (!agent) {
        logError('Killed event received without agent data')
        return
      }

      this.commsInterface?.notify({
        method: 'agentic/log',
        data: {
          level: 'info',
          message: `Agent with ID ${agent.id} was killed`,
        },
      })

      logDebug(`Agent with ID ${agent.id} was killed`)
      this.stateManager?.deleteItem('agent')
    })

    this.agentManager.init()
  }

  private async _process_payload(payload: ASMPayload) {
    // Structural validation already done by Check(ASMPayloadSchema) before this call.
    switch (payload.data.method) {
      case 'client/init':
        this._initAgentManager(payload.data.params)
        break

      case 'client/dispose':
        this.dispose()
        break

      case 'client/ask':
        // await this._ask({
        //   id: payload.id,
        //   data: payload.params.ask,
        // })
        break

      case 'client/get_history':
        await this._getHistory(payload.data.params)
        break

      case 'client/terminal':
        this.terminalHandler?.handleResponse(payload.data.params)
        break

      default:
        break
    }
  }

  // private async _ask(payload: ASMPayload) {
  //   if (!this.activeProvider || !this.activeSessionId) {
  //     throw new Error("No provider initialized. Call 'init' first.")
  //   }

  //   const userPrompt = payload.params.prompt || ''
  //   const contexts: NeovimContext[] = payload.params.contexts || []

  //   // Ingest Contexts
  //   const ingester = new ContextIngester(this.activeSessionId)
  //   const synthesizedPrompt = await ingester.synthesizePrompt(
  //     userPrompt,
  //     contexts,
  //   )

  //   // Record User Message Locally
  //   addMessage(this.activeSessionId, 'user', synthesizedPrompt)

  //   // Fetch ACP Connection
  //   const conn = this.activeProvider.getConnection()

  //   notify('chat_stream', {
  //     text: `(Forwarding to ACP Agent)\n\n`,
  //   })

  //   // Call Provider utilizing official ACP Protocol
  //   try {
  //     let streamedResponse = ''

  //     // Listen to asynchronous Text chunks and pipe to Neovim UI + Local Buffer
  //     this.activeProvider.onSessionUpdate = (text: string) => {
  //       streamedResponse += text
  //       notify('chat_stream', {
  //         text: text,
  //       })
  //     }

  //     await conn.prompt({
  //       sessionId: this.activeSessionId,
  //       prompt: [
  //         {
  //           type: 'text',
  //           text: synthesizedPrompt,
  //         },
  //       ],
  //     })

  //     // Generation concluded successfully
  //     addMessage(
  //       this.activeSessionId,
  //       'assistant',
  //       streamedResponse || '(No content returned)',
  //     )

  //     respond(payload.id, { success: true })
  //   } catch (e) {
  //     notify('chat_stream', {
  //       text: `\n\n**Agent Error:** ${e}\n`,
  //     })
  //     respond(payload.id, null, e)
  //   }
  // }

  private async _getHistory(params: ASMPayloadParams['client/get_history']) {
    if (!params || !params.sessionId) {
      throw new Error('sessionId is required for get_history')
    }
    // const history = getMessages(params.sessionId)
    // this.commsInterface?.respond({
    //   id: null,
    //   result: { history },
    // })
  }
}
