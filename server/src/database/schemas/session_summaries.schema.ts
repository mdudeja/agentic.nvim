import { index, sqliteTable, text } from 'drizzle-orm/sqlite-core'
import { baseSchema } from './common.schema'
import { sessions } from './sessions.schema'

export const session_summaries = sqliteTable(
  'session_summaries',
  {
    ...baseSchema,
    session_id: text()
      .references(() => sessions.id, { onDelete: 'cascade' })
      .notNull(),
    summary: text().notNull(),
  },
  (table) => [
    index('idx_session_summary_session_id').on(table.session_id),
    index('idx_session_summary_created_at').on(table.created_at),
    index('idx_session_summary_updated_at').on(table.updated_at),
  ],
)

export type SessionSummary = {
  Insert: typeof session_summaries.$inferInsert
  Select: typeof session_summaries.$inferSelect
  Update: Partial<typeof session_summaries.$inferSelect>
}
