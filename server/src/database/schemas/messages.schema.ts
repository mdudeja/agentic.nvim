import { index, sqliteTable, text } from 'drizzle-orm/sqlite-core'
import { baseSchema } from './common.schema'
import { sessions } from './sessions.schema'
import type { ContentBlock } from '@agentclientprotocol/sdk'
export const messages = sqliteTable(
  'messages',
  {
    ...baseSchema,
    prompt: text({ mode: 'json' }).notNull().$type<ContentBlock[]>(),
    response: text({ mode: 'json' }).$type<ContentBlock[]>(),
    session_id: text()
      .references(() => sessions.id, { onDelete: 'cascade' })
      .notNull(),
  },
  (table) => [
    index('idx_message_session_id').on(table.session_id),
    index('idx_message_created_at').on(table.created_at),
    index('idx_message_updated_at').on(table.updated_at),
  ],
)

export type Message = {
  Insert: typeof messages.$inferInsert
  Select: typeof messages.$inferSelect
  Update: Partial<typeof messages.$inferSelect>
}
