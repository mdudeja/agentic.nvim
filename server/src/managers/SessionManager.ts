import { EventEmitter } from 'node:events'
import { AgenticDB } from 'src/database/AgenticDB'
import type { ASMState } from 'src/state/IASMState'

export class SessionManager extends EventEmitter {
  private db: ReturnType<AgenticDB['getDB']> | null = null
  private sessions: Map<string, ASMState['session']> = new Map()
  private activeSessionId: string | null = null

  constructor() {
    super()
    const dbInstance = AgenticDB.getInstance()
    this.db = dbInstance.getDB()
  }
}
