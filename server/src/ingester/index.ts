import { type Message, getMessages } from '../database/db'

// The shape of context payloads arriving from Neovim
export interface NeovimContext {
  type: 'selection' | 'file' | 'workspace' | 'keymaps' | 'diagnostics'
  content: string
  metadata?: Record<string, any>
}

// Ingesters evaluate what context specifically needs to be attached to the PROMPT
// based on what the user has requested + what is already known in the session history.
export class ContextIngester {
  constructor(private sessionId: string) {}

  public async synthesizePrompt(
    userPrompt: string,
    contexts: NeovimContext[],
  ): Promise<string> {
    let finalPrompt = ''

    // Check if this is a brand new session or an existing one
    const history = getMessages(this.sessionId)
    const isNewSession = history.length === 0

    // If we have contexts, we need to append them dynamically
    if (contexts && contexts.length > 0) {
      finalPrompt += '### Provided Contexts\n\n'

      for (const ctx of contexts) {
        // Example Logic: Only inject heavy payloads if they aren't already in history
        if (ctx.type === 'keymaps' && !isNewSession) {
          const hasKeymapsPreviously = history.some((m) =>
            m.content.includes('### Keymap Snapshot'),
          )
          if (hasKeymapsPreviously) {
            // Skip injecting keymaps again, the model already has it in its memory window
            continue
          }
        }

        // Format the context block
        finalPrompt += `--- Context Block: ${ctx.type.toUpperCase()} ---\n`
        finalPrompt += `${ctx.content}\n\n`
      }
    }

    // Add the main user prompt
    finalPrompt += `### User Query\n\n${userPrompt}`

    return finalPrompt
  }
}
