/**
 * TypeBox schemas for the Agentic Server JSON-RPC interface.
 *
 * These schemas are the single source of truth for:
 *  1. TypeScript types (via Static<>) — replacing hand-written types in ICommsInterface.ts
 *  2. Runtime validation (via Check() from typebox/value) — incoming message validation
 *  3. OpenRPC spec generation — schema values drop directly into the spec as JSON Schema
 *
 * Adding a new method:
 *  1. Define its params schema here with Type.Object(...)
 *  2. Add it to ASMPayloadDataSchema's union
 *  3. Export the Static<> type alias
 *  4. Add it to openrpc/spec.ts
 */

import { Type } from 'typebox'
import type { Static } from 'typebox/type'
import { PROVIDERS } from 'src/data/providers'

// ---------------------------------------------------------------------------
// Shared / primitive schemas
// ---------------------------------------------------------------------------

export const ProviderSchema = Type.Union(
  Object.keys(PROVIDERS).map((k) => Type.Literal(k)),
)

export const LogLevelSchema = Type.Union([
  Type.Literal('info'),
  Type.Literal('warn'),
  Type.Literal('error'),
])

export const NeovimContextSchema = Type.Object({
  type: Type.Union([
    Type.Literal('selection'),
    Type.Literal('file'),
    Type.Literal('workspace'),
    Type.Literal('keymaps'),
    Type.Literal('diagnostics'),
  ]),
  content: Type.String(),
  metadata: Type.Optional(Type.Record(Type.String(), Type.Unknown())),
})

// EnvVariable and TerminalExitStatus come from @agentclientprotocol/sdk
const EnvVariableSchema = Type.Object({}, { additionalProperties: true })
const TerminalExitStatusSchema = Type.Object({}, { additionalProperties: true })

// ---------------------------------------------------------------------------
// CLIENT → SERVER: per-method param schemas
// ---------------------------------------------------------------------------

export const InitParamsSchema = Type.Object({
  provider: ProviderSchema,
  cwd: Type.String(),
  sessionName: Type.Optional(Type.String()),
})

export const DisposeParamsSchema = Type.Object({
  reason: Type.Optional(Type.String()),
  agentId: Type.Optional(Type.String()),
})

export const AskParamsSchema = Type.Object({
  prompt: Type.String(),
  contexts: Type.Optional(Type.Array(NeovimContextSchema)),
})

export const GetHistoryParamsSchema = Type.Object({
  sessionId: Type.String(),
})

export const AnswerParamsSchema = Type.Object({
  questionId: Type.String(),
  answer: Type.String(),
})

// Terminal response sub-schemas (client replies to agentic/terminal requests)
const TerminalResponseCreateSchema = Type.Object({
  request: Type.Literal('create'),
  params: Type.Object({
    terminalId: Type.String(),
    jobId: Type.Optional(Type.Number()),
  }),
})
const TerminalResponseGetOutputSchema = Type.Object({
  request: Type.Literal('get_output'),
  params: Type.Object({
    stdout: Type.String(),
    stderr: Type.String(),
    exitStatus: Type.Optional(TerminalExitStatusSchema),
    truncated: Type.Optional(Type.Boolean()),
  }),
})
const TerminalResponseWaitExitSchema = Type.Object({
  request: Type.Literal('wait_exit'),
  params: Type.Object({ exitStatus: TerminalExitStatusSchema }),
})
const TerminalResponseKillSchema = Type.Object({
  request: Type.Literal('kill'),
  params: Type.Object({ success: Type.Boolean() }),
})
const TerminalResponseReleaseSchema = Type.Object({
  request: Type.Literal('release'),
  params: Type.Object({ success: Type.Boolean() }),
})

export const TerminalResponseFromNvimSchema = {
  create: TerminalResponseCreateSchema,
  get_output: TerminalResponseGetOutputSchema,
  wait_exit: TerminalResponseWaitExitSchema,
  kill: TerminalResponseKillSchema,
  release: TerminalResponseReleaseSchema,
}

export const TerminalResponseSchema = Type.Union([
  TerminalResponseCreateSchema,
  TerminalResponseGetOutputSchema,
  TerminalResponseWaitExitSchema,
  TerminalResponseKillSchema,
  TerminalResponseReleaseSchema,
])

export const TerminalParamsSchema = Type.Object({
  requestId: Type.String(),
  error: Type.Optional(Type.Any()),
  response: TerminalResponseSchema,
})

// ---------------------------------------------------------------------------
// CLIENT → SERVER: full payload schemas (method + params per variant)
// ---------------------------------------------------------------------------

const InitPayloadSchema = Type.Object({
  method: Type.Literal('client/init'),
  params: InitParamsSchema,
})
const DisposePayloadSchema = Type.Object({
  method: Type.Literal('client/dispose'),
  params: DisposeParamsSchema,
})
const AskPayloadSchema = Type.Object({
  method: Type.Literal('client/ask'),
  params: AskParamsSchema,
})
const GetHistoryPayloadSchema = Type.Object({
  method: Type.Literal('client/get_history'),
  params: GetHistoryParamsSchema,
})
const AnswerPayloadSchema = Type.Object({
  method: Type.Literal('client/answer'),
  params: AnswerParamsSchema,
})
const TerminalPayloadSchema = Type.Object({
  method: Type.Literal('client/terminal'),
  params: TerminalParamsSchema,
})

export const ASMPayloadDataSchema = Type.Union([
  InitPayloadSchema,
  DisposePayloadSchema,
  AskPayloadSchema,
  GetHistoryPayloadSchema,
  AnswerPayloadSchema,
  TerminalPayloadSchema,
])

export const ASMPayloadSchema = Type.Object({
  jsonrpc: Type.Literal('2.0'),
  data: ASMPayloadDataSchema,
})

// ---------------------------------------------------------------------------
// SERVER → CLIENT: notification schemas (outgoing — for documentation only,
// not validated since we construct these ourselves)
// ---------------------------------------------------------------------------

// Respond notifications (server → client)
export const RespondParamsSchema = Type.Object({
  id: Type.Union([Type.String(), Type.Null()]),
  error: Type.Optional(Type.Any()),
  result: Type.Optional(Type.Any()),
})

// Log notifications (server → client)
export const LogNotificationParamsSchema = Type.Object({
  method: Type.Literal('agentic/log'),
  data: Type.Object({
    level: LogLevelSchema,
    message: Type.String(),
  }),
})

// Question notifications (server → client)
export const QuestionNotificationParamsSchema = Type.Object({
  method: Type.Literal('agentic/question'),
  data: Type.Object({
    questionId: Type.Optional(Type.String()),
    question: Type.String(),
  }),
})

// Terminal requests (server → client)
export const TerminalRequestToNvimSchema = {
  create: Type.Object({
    requestId: Type.String(),
    terminalId: Type.String(),
    command: Type.String(),
    cwd: Type.Optional(Type.String()),
    env: Type.Optional(Type.Array(EnvVariableSchema)),
    outputByteLimit: Type.Optional(Type.Number()),
  }),
  get_output: Type.Object({
    requestId: Type.String(),
    terminalId: Type.String(),
  }),
  wait_exit: Type.Object({
    requestId: Type.String(),
    terminalId: Type.String(),
  }),
  kill: Type.Object({
    requestId: Type.String(),
    terminalId: Type.String(),
    signal: Type.String(),
  }),
  release: Type.Object({
    requestId: Type.String(),
    terminalId: Type.String(),
  }),
} as const

// Terminal notifications (server → client)
export const TerminalNotificationParamsSchema = Type.Union([
  Type.Object({
    method: Type.Literal('agentic/terminal'),
    data: TerminalRequestToNvimSchema.create,
  }),
  Type.Object({
    method: Type.Literal('agentic/terminal'),
    data: TerminalRequestToNvimSchema.get_output,
  }),
  Type.Object({
    method: Type.Literal('agentic/terminal'),
    data: TerminalRequestToNvimSchema.wait_exit,
  }),
  Type.Object({
    method: Type.Literal('agentic/terminal'),
    data: TerminalRequestToNvimSchema.kill,
  }),
  Type.Object({
    method: Type.Literal('agentic/terminal'),
    data: TerminalRequestToNvimSchema.release,
  }),
])

// ---------------------------------------------------------------------------
// Static type aliases for exported schemas
// ---------------------------------------------------------------------------

// Client → Server types
export type NeovimContext = Static<typeof NeovimContextSchema>
export type InitParams = Static<typeof InitParamsSchema>
export type DisposeParams = Static<typeof DisposeParamsSchema>
export type AskParams = Static<typeof AskParamsSchema>
export type GetHistoryParams = Static<typeof GetHistoryParamsSchema>
export type AnswerParams = Static<typeof AnswerParamsSchema>
export type TerminalResponse = Static<typeof TerminalResponseSchema>
export type TerminalParams = Static<typeof TerminalParamsSchema>
export type ASMPayload = Static<typeof ASMPayloadSchema>

export type TerminalResponseFromNvim = {
  [K in keyof typeof TerminalResponseFromNvimSchema]: Static<
    (typeof TerminalResponseFromNvimSchema)[K]
  >
}

// Utility: extract per-method params type from the union
export type ASMPayloadParams = {
  'client/init': InitParams
  'client/dispose': DisposeParams
  'client/ask': AskParams
  'client/get_history': GetHistoryParams
  'client/answer': AnswerParams
  'client/terminal': TerminalParams
}

// Server → Client types
export type RespondParams = Static<typeof RespondParamsSchema>
export type LogNotificationParams = Static<typeof LogNotificationParamsSchema>
export type QuestionNotificationParams = Static<
  typeof QuestionNotificationParamsSchema
>
export type TerminalRequestToNvim = {
  [K in keyof typeof TerminalRequestToNvimSchema]: Static<
    (typeof TerminalRequestToNvimSchema)[K]
  >
}
export type TerminalNotificationParams = Static<
  typeof TerminalNotificationParamsSchema
>
