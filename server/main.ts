import type { ASMState } from 'src/state'
import { type PROVIDERS, ProviderClient } from './src/acp/Client'
import { createSession, addMessage, getMessages } from './src/database/db'
import { ContextIngester, type NeovimContext } from './src/ingester/index'
import { respond, notify } from './src/utils/messaging'
import * as readline from 'readline/promises'

export type ASMMethod = 'init' | 'ask' | 'get_history'

export type ASMPayloadParams = {
  config?: ASMState
  query?: {
    prompt: string
    contexts?: NeovimContext[]
  }
}

export type ASMPayload = {
  jsonrpc: '2.0'
  id: string | number
  method: ASMMethod
  params: ASMPayloadParams
}

export class AgenticServer {
  static instance: AgenticServer | null = null
  private activeProvider: ProviderClient | null = null
  private activeSessionId: string | null = null
  private rl: readline.Interface | null = null

  constructor() {
    this._setup()
      .then(() => {
        console.log('[AgenticServer] Initialized successfully.')
      })
      .catch((err) => {
        console.error('[AgenticServer] Initialization failed:', err)
      })
  }

  static getInstance() {
    if (!AgenticServer.instance) {
      AgenticServer.instance = new AgenticServer()
    }
    return AgenticServer.instance
  }

  getRl() {
    if (!this.rl) {
      throw new Error('Readline interface not initialized yet.')
    }
    return this.rl
  }

  private async _setup() {
    console.log('[AgenticServer] Starting Agentic Server...')
    this.rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
      terminal: false,
    })

    this.rl.on('line', async (line) => {
      if (!line.trim()) return

      try {
        const payload: ASMPayload = JSON.parse(line)
        if (payload.jsonrpc !== '2.0' || !payload.method) return

        const { method } = payload

        switch (method) {
          case 'init':
            await this._init(payload)
            break

          case 'ask':
            await this._ask(payload)
            break

          case 'get_history':
            await this._getHistory(payload)
            break

          default:
            throw new Error(`Unknown method: ${method}`)
        }
      } catch (err) {
        const errObj = err as Error
        notify('log', {
          level: 'error',
          message: errObj.message || String(errObj),
        })
      }
    })
    console.log('[AgenticServer] Server setup complete. Awaiting commands...')
  }

  private async _init(payload: ASMPayload) {
    const providerId = payload.params.provider || 'copilot'

    if (this.activeProvider) {
      this.activeProvider.disconnect()
    }

    this.activeProvider = new ProviderClient(providerId)
    const { agentCapabilities } = await this.activeProvider.connect()

    this.activeSessionId = payload.params.sessionId || `session_${Date.now()}`
    createSession(
      this.activeSessionId,
      providerId,
      payload.params.sessionName as string | undefined,
    )

    respond(payload.id, {
      success: true,
      sessionId: this.activeSessionId,
      provider: providerId,
      capabilities: agentCapabilities,
    })
  }

  private async _ask(payload: ASMPayload) {
    if (!this.activeProvider || !this.activeSessionId) {
      throw new Error("No provider initialized. Call 'init' first.")
    }

    const userPrompt = payload.params.prompt || ''
    const contexts: NeovimContext[] = payload.params.contexts || []

    // Ingest Contexts
    const ingester = new ContextIngester(this.activeSessionId)
    const synthesizedPrompt = await ingester.synthesizePrompt(
      userPrompt,
      contexts,
    )

    // Record User Message Locally
    addMessage(this.activeSessionId, 'user', synthesizedPrompt)

    // Fetch ACP Connection
    const conn = this.activeProvider.getConnection()

    notify('chat_stream', {
      text: `(Forwarding to ACP Agent)\n\n`,
    })

    // Call Provider utilizing official ACP Protocol
    try {
      let streamedResponse = ''

      // Listen to asynchronous Text chunks and pipe to Neovim UI + Local Buffer
      this.activeProvider.onSessionUpdate = (text: string) => {
        streamedResponse += text
        notify('chat_stream', {
          text: text,
        })
      }

      await conn.prompt({
        sessionId: this.activeSessionId,
        prompt: [
          {
            type: 'text',
            text: synthesizedPrompt,
          },
        ],
      })

      // Generation concluded successfully
      addMessage(
        this.activeSessionId,
        'assistant',
        streamedResponse || '(No content returned)',
      )

      respond(payload.id, { success: true })
    } catch (e) {
      notify('chat_stream', {
        text: `\n\n**Agent Error:** ${e}\n`,
      })
      respond(payload.id, null, e)
    }
  }

  private async _getHistory(payload: ASMPayload) {
    if (!payload.params.sessionId) {
      throw new Error('sessionId is required for get_history')
    }
    const history = getMessages(payload.params.sessionId)
    respond(payload.id, { history })
  }
}
