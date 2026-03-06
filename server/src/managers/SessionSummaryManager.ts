import type { SummaryEvents } from 'src/data/events'
import { BaseManager } from './BaseManager'
import { AgenticDB } from 'src/database/AgenticDB'
import type { MessageManager } from './MessageManager'

export class SessionSummaryManager extends BaseManager<SummaryEvents> {
  private db: ReturnType<AgenticDB['getDB']>

  constructor(private readonly message_manager_instance: MessageManager) {
    super()
    const dbInstance = AgenticDB.getInstance()
    this.db = dbInstance.getDB()
  }

  async createSummary(sessionId: string) {
    const messages =
      await this.message_manager_instance.getAllForSession(sessionId)

    if (!messages || messages.length === 0) {
      this.emit('summary.error', 'No messages found for session to summarize')
      return
    }

    //TODO: Implement actual summarization logic here
  }
}
