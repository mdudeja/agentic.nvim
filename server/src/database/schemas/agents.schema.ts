import { index, sqliteTable, text } from 'drizzle-orm/sqlite-core'
import { baseSchema, providerSchema } from './common.schema'

export const agents = sqliteTable(
  'agents',
  {
    ...baseSchema,
    ...providerSchema,
    cwd: text().notNull(),
    env: text({ mode: 'json' }).$type<Record<string, string>>(),
  },
  (table) => [
    index('idx_agent_provider_cwd').on(table.provider_name, table.cwd),
    index('idx_agent_created_at').on(table.created_at),
    index('idx_agent_updated_at').on(table.updated_at),
  ],
)

export type Agent = {
  Insert: typeof agents.$inferInsert
  Select: typeof agents.$inferSelect
  Update: Partial<typeof agents.$inferSelect>
}
