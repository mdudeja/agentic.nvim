import type { MessageEvents } from 'src/data/events'
import { BaseManager } from './BaseManager'
import { AgenticDB } from 'src/database/AgenticDB'
import { messages, type Message } from 'src/database/schemas/messages.schema'
import { eq } from 'drizzle-orm'

export class MessageManager extends BaseManager<MessageEvents> {
  private db: ReturnType<AgenticDB['getDB']>

  constructor() {
    super()
    const dbInstance = AgenticDB.getInstance()
    this.db = dbInstance.getDB()
  }

  init() {
    this.emit('message.manager_init', undefined)
  }

  async savePrompt(message: Message['Insert']) {
    const insertedMessage = await this.db
      .insert(messages)
      .values(message)
      .returning()
      .then((result) => result[0])

    if (!insertedMessage) {
      this.emit('message.error', 'Failed to save message')
      return
    }

    this.emit('message.prompted', insertedMessage)
  }

  async saveResponse(
    messageId: string,
    responseContent: Message['Select']['response'],
  ) {
    const updatedMessage = await this.db
      .update(messages)
      .set({ response: responseContent })
      .where(eq(messages.id, messageId))
      .returning()
      .then((result) => result[0])

    if (!updatedMessage) {
      this.emit('message.error', 'Failed to update message with response')
      return
    }

    this.emit('message.responded', updatedMessage)
  }

  async getAllForSession(sessionId: string) {
    const sessionMessages = await this.db
      .select()
      .from(messages)
      .where(eq(messages.session_id, sessionId))
      .orderBy(messages.created_at)

    return sessionMessages
  }
}
