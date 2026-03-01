import {
  createInsertSchema,
  createSelectSchema,
  createUpdateSchema,
} from 'drizzle-orm/typebox'
import { agents, messages, session_summaries, sessions } from './schemas'
import { Value } from 'typebox/value'
import type { TSchema } from 'typebox'

export const AgentInsertSchema = createInsertSchema(agents)
export const AgentSelectSchema = createSelectSchema(agents)
export const AgentUpdateSchema = createUpdateSchema(agents)

export const SessionInsertSchema = createInsertSchema(sessions)
export const SessionSelectSchema = createSelectSchema(sessions)
export const SessionUpdateSchema = createUpdateSchema(sessions)

export const MessageInsertSchema = createInsertSchema(messages)
export const MessageSelectSchema = createSelectSchema(messages)
export const MessageUpdateSchema = createUpdateSchema(messages)

export const SessionSummaryInsertSchema = createInsertSchema(session_summaries)
export const SessionSummarySelectSchema = createSelectSchema(session_summaries)
export const SessionSummaryUpdateSchema = createUpdateSchema(session_summaries)

export function isValid<T extends TSchema>(schema: T, data: unknown): boolean {
  return Value.Check(schema, data)
}
