import type { Subprocess } from 'bun'
import type { Agent, Session } from 'src/database/schemas'

export type ASMState = {
  agent?: Agent['Select'] & {
    process?: Subprocess
  }
  session?: Session['Select']
}

export interface IASMState {
  setItem(key: keyof ASMState, value: any): void
  updateItem(key: keyof ASMState, value: any): void
  deleteItem(key: keyof ASMState): void
  getItem(key: keyof ASMState): any
  getState(): ASMState
}
