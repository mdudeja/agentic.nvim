import { index, sqliteTable, text } from 'drizzle-orm/sqlite-core'
import { baseSchema, messageRoleSchema } from './common.schema'
import { sessions } from './sessions.schema'
export const messages = sqliteTable(
  'messages',
  {
    ...baseSchema,
    ...messageRoleSchema,
    content: text().notNull(),
    session_id: text()
      .references(() => sessions.id, { onDelete: 'cascade' })
      .notNull(),
  },
  (table) => [
    index('idx_message_session_id').on(table.session_id),
    index('idx_message_role').on(table.role),
    index('idx_message_created_at').on(table.created_at),
    index('idx_message_updated_at').on(table.updated_at),
  ],
)

export type Message = {
  Insert: typeof messages.$inferInsert
  Select: typeof messages.$inferSelect
  Update: Partial<typeof messages.$inferSelect>
}
