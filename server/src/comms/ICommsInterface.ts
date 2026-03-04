import type {
  LogNotificationParams,
  QuestionNotificationParams,
  TerminalNotificationParams,
  RespondParams,
  ASMPayloadParams,
} from 'src/openrpc/schemas'

// ---------------------------------------------------------------------------
// Incoming RPC types
// ---------------------------------------------------------------------------
export type {
  ASMPayload,
  ASMPayloadParams,
  NeovimContext,
  TerminalRequestToNvim,
  TerminalResponseFromNvim,
} from 'src/openrpc/schemas'

// ---------------------------------------------------------------------------
// Outgoing RPC types
// ---------------------------------------------------------------------------

export type {
  RespondParams,
  LogNotificationParams,
  QuestionNotificationParams,
  TerminalNotificationParams,
} from 'src/openrpc/schemas'

// ---------------------------------------------------------------------------
// SERVER → CLIENT notification types
// ---------------------------------------------------------------------------

export type NotifyMethods =
  | 'agentic/log'
  | 'agentic/terminal'
  | 'agentic/question'

export type NotifyParams =
  | LogNotificationParams
  | TerminalNotificationParams
  | QuestionNotificationParams

// ---------------------------------------------------------------------------
// ASMMethod union — kept for switch/case exhaustiveness checks in main.ts
// ---------------------------------------------------------------------------
export type ASMMethod = keyof ASMPayloadParams

// ---------------------------------------------------------------------------
// ICommsInterface contract
// ---------------------------------------------------------------------------
export interface ICommsInterface {
  init(port?: number): Promise<void>
  onMessage(callback: (message: string) => Promise<void>): void
  onClose(callback: () => void): void
  respond(params: RespondParams): void
  notify(params: NotifyParams): void
  question(params: QuestionNotificationParams['data']): Promise<string>
  dispose(): void
}
