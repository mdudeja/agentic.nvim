import { PROVIDERS, ProviderClient } from './src/providers/index'
import { createSession, addMessage, getMessages } from './src/history/db'
import { ContextIngester, type NeovimContext } from './src/ingester/index'
import * as readline from 'readline'

// Setup stdio JSON-RPC interface for Neovim
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false,
})

let activeProvider: ProviderClient | null = null
let activeSessionId: string | null = null

// Helper to send JSON-RPC responses back to Neovim
function respond(id: string | number, result: any, error?: any) {
  process.stdout.write(
    JSON.stringify({
      jsonrpc: '2.0',
      id,
      result: error ? undefined : result,
      error: error
        ? { code: -32000, message: error.message || String(error) }
        : undefined,
    }) + '\n',
  )
}

// Helper to send server push notifications back to Neovim
function notify(method: string, params: any) {
  process.stdout.write(
    JSON.stringify({
      jsonrpc: '2.0',
      method,
      params,
    }) + '\n',
  )
}

rl.on('line', async (line) => {
  if (!line.trim()) return

  try {
    const payload = JSON.parse(line)
    if (payload.jsonrpc !== '2.0' || !payload.method) return

    const { method, params, id } = payload

    switch (method) {
      case 'init':
        // Initialize or change the active provider
        const providerId = params.provider || 'copilot'
        const pConfig = PROVIDERS[providerId]
        if (!pConfig) throw new Error(`Unknown provider: ${providerId}`)

        if (activeProvider) {
          await activeProvider.disconnect()
        }

        activeProvider = new ProviderClient(pConfig)
        const capabilities = await activeProvider.connect()

        // Create or resume the local history session
        activeSessionId = (params.sessionId ||
          `session_${Date.now()}`) as string
        createSession(
          activeSessionId,
          providerId,
          params.sessionName as string | undefined,
        )

        respond(id, {
          success: true,
          sessionId: activeSessionId,
          provider: providerId,
          capabilities,
        })
        break

      case 'ask':
        if (!activeProvider)
          throw new Error("No provider initialized. Call 'init' first.")
        if (!activeSessionId) throw new Error('No active session.')

        const userPrompt = params.prompt
        const contexts: NeovimContext[] = params.contexts || []

        // Ingest Contexts
        const ingester = new ContextIngester(activeSessionId)
        const synthesizedPrompt = await ingester.synthesizePrompt(
          userPrompt,
          contexts,
        )

        // Record User Message Locally
        addMessage(activeSessionId, 'user', synthesizedPrompt)

        // Fetch ACP Connection
        const conn = activeProvider.getConnection()

        notify('chat_stream', {
          text: `(Forwarding to ACP Agent)\n\n`,
        })

        // Call Provider utilizing official ACP Protocol
        try {
          let streamedResponse = ''

          // Listen to asynchronous Text chunks and pipe to Neovim UI + Local Buffer
          activeProvider!.onSessionUpdate = (text: string) => {
            streamedResponse += text
            notify('chat_stream', {
              text: text,
            })
          }

          await conn.prompt({
            sessionId: activeSessionId,
            prompt: [
              {
                type: 'text',
                text: synthesizedPrompt,
              },
            ],
          })

          // Generation concluded successfully
          addMessage(
            activeSessionId,
            'assistant',
            streamedResponse || '(No content returned)',
          )

          respond(id, { success: true })
        } catch (e) {
          notify('chat_stream', {
            text: `\n\n**Agent Error:** ${e}\n`,
          })
          respond(id, null, e)
        }
        break

      case 'get_history':
        if (!params.sessionId) throw new Error('sessionId required')
        const history = getMessages(params.sessionId)
        respond(id, { history })
        break

      default:
        throw new Error(`Unknown method: ${method}`)
    }
  } catch (err) {
    // If it's a request (has id), send an error response. Otherwise log.
    // However, since we're using stdio, avoid raw console.error breaking Neovim's JSON parser unless wrapped.
    const errObj = err as Error
    notify('log', {
      level: 'error',
      message: errObj.message || String(errObj),
    })
  }
})
