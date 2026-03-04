import type {
  AvailableCommand,
  ClientSideConnection,
  InitializeResponse,
  SessionModelState,
  SessionModeState,
} from '@agentclientprotocol/sdk'
import type { Subprocess } from 'bun'
import type { AcpClient } from 'src/acp/Client'
import type { Agent, Session } from 'src/database/schemas'

export type ASMState = {
  agent?: Agent['Select'] & {
    process?: Subprocess
  }
  session?: Session['Select'] & {
    modes: SessionModeState | null
    models: SessionModelState | null
    availableCommands: AvailableCommand[]
  }
  connection?: {
    csc?: ClientSideConnection
    client?: AcpClient
    initResponse?: InitializeResponse
  }
}

export interface IASMState {
  setItem(key: keyof ASMState, value: any): void
  updateItem(key: keyof ASMState, value: any): void
  deleteItem(key: keyof ASMState): void
  getItem(key: keyof ASMState): any
  getState(): ASMState
}
