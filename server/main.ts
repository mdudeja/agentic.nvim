import { AgentManager } from 'src/managers/AgentManager'
import { Providers } from 'src/data/providers'
import { resolvePath } from 'src/utils/paths'
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
import { ASMStateManager } from 'src/state'
import { SessionManager } from 'src/managers/SessionManager'

export class AgenticServer {
  private stateManager: ASMStateManager
  private commsInterface: ICommsInterface
  private agentManager: AgentManager | null = null
  private sessionManager: SessionManager | null = null

  constructor(config: { mode: 'rpc' | 'server'; port?: number }) {
    logInfo(`Starting Agentic Server in ${config.mode.toUpperCase()} mode...`)
    this.stateManager = new ASMStateManager()
    this.commsInterface =
      config.mode === 'rpc'
        ? new ReadlineCommsInterface()
        : new WebsocketCommsInterface()
  }

  /**
   * RPC mode (default): listen for JSON-RPC payloads on stdin and respond on stdout.
   */
  async init() {
    try {
      this._initCommsInterface()
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
    return this.stateManager.getState()
  }

  dispose() {
    if (this.stateManager) {
      this.stateManager.dispose()
    }

    if (this.sessionManager) {
      this.sessionManager.dispose()
    }

    if (this.agentManager) {
      this.agentManager.dispose()
    }

    if (this.commsInterface) {
      this.commsInterface.dispose()
    }

    process.exit(0)
  }

  private _initCommsInterface() {
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

  private async _initAgentManager(params: ASMPayloadParams['client/init']) {
    const resolvedCwd = resolvePath(params.cwd)
    const providerId = params.provider || 'copilot'

    logDebug(
      `Initializing agent with provider ${providerId} in directory ${resolvedCwd}`,
    )

    if (!this.agentManager) {
      this.agentManager = new AgentManager(
        Providers[providerId],
        resolvedCwd,
        this,
      )
    }

    this.agentManager.on('agent.error', (errorMessage) => {
      logError(`Agent error: ${errorMessage}`)
      this.commsInterface?.notify({
        method: 'agentic/log',
        data: {
          level: 'error',
          message: `Agent error: ${errorMessage}`,
        },
      })
    })

    this.agentManager.on('agent.loaded', (agent) => {
      if (!agent) {
        logError('Loaded event received without agent data')
        const err = new Error('Failed to load agent')
        this.commsInterface?.notify({
          method: 'agentic/log',
          data: {
            level: 'error',
            message: `Failed to load agent: ${err.message}`,
          },
        })
        return
      }

      logDebug(`Agent loaded with ID ${agent.id}`)
      this.stateManager?.setItem('agent', agent)

      this.agentManager?.spawn()
    })

    this.agentManager.on('agent.spawned', async (agent) => {
      if (!agent) {
        logError('Spawned event received without agent data')
        const err = new Error('Failed to spawn agent')
        this.commsInterface?.notify({
          method: 'agentic/log',
          data: {
            level: 'error',
            message: `Failed to spawn agent: ${err.message}`,
          },
        })
        return
      }

      logDebug(`Agent spawned with ID ${agent.id}`)
      this.stateManager?.setItem('agent', agent)
      this.commsInterface?.respond({
        method: 'client/init',
        id: params.requestId,
        result: { success: true, agentId: agent.id },
      })

      if (!this.agentManager) {
        logError('AgentManager not initialized when handling spawned event')
        return
      }

      const connectData = await this.agentManager.connect()

      if (!connectData) {
        logError('Failed to establish connection in spawned event')
        return
      }

      const { connection, client, initResponse } = connectData

      this.stateManager?.setItem('connection', {
        csc: connection,
        client,
        initResponse,
      })
    })

    this.agentManager.on('agent.connected', async (agent) => {
      if (!agent) {
        logError('Connected event received without agent data')
        return
      }

      logDebug(`Agent with ID ${agent.id} connected`)
      this.commsInterface?.notify({
        method: 'agentic/log',
        data: {
          level: 'info',
          message: `Agent with ID ${agent.id} connected`,
        },
      })

      this.stateManager?.setItem('agent', agent)

      await this._initSessionManager()
    })

    this.agentManager.on('agent.killed', (agent) => {
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
      this.stateManager?.deleteItem('connection')
    })

    await this.agentManager.init()
  }

  private async _initSessionManager() {
    this.sessionManager = new SessionManager(this)

    this.sessionManager.on('session.error', (errorMessage) => {
      logError(`Session error: ${errorMessage}`)
      this.commsInterface?.notify({
        method: 'agentic/log',
        data: {
          level: 'error',
          message: `Session error: ${errorMessage}`,
        },
      })
    })

    this.sessionManager.on('session.loaded', (session) => {
      if (!session) {
        logError('Loaded event received without session data')
        const err = new Error('Failed to load session')
        this.commsInterface?.notify({
          method: 'agentic/log',
          data: {
            level: 'error',
            message: `Failed to load session: ${err.message}`,
          },
        })
        return
      }

      logDebug(`Session loaded with ID ${session.id}`)
      this.stateManager?.setItem('session', session)

      this.commsInterface?.notify({
        method: 'agentic/log',
        data: {
          level: 'info',
          message: `Session loaded with ID ${session.id} and name ${session.name}`,
        },
      })
    })

    await this.sessionManager.init()
  }

  private async _process_payload(payload: ASMPayload) {
    // Structural validation already done by Check(ASMPayloadSchema) before this call.
    switch (payload.data.method) {
      case 'client/init':
        await this._initAgentManager(payload.data.params)
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

      case 'client/terminal':
        this.agentManager?.handleTerminalResponse(payload.data.params)
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
}
