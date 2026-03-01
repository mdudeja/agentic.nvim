import { getNowMillis } from '../../utils/datetimeUtils'
import * as t from 'drizzle-orm/sqlite-core'
import { createId } from '@paralleldrive/cuid2'
import type { Providers } from 'src/data/providers'

// Enums
const customEnum = <T>(name: string) =>
  t.customType<{
    data: T
  }>({
    dataType() {
      return 'text'
    },
  })(name)

// Common Schemas
export const timestampsSchema = {
  created_at: t
    .integer({ mode: 'number' })
    .notNull()
    .$default(() => getNowMillis()),
  updated_at: t
    .integer({ mode: 'number' })
    .notNull()
    .$onUpdate(() => getNowMillis()),
}

export const baseSchema = {
  id: t
    .text()
    .primaryKey()
    .$defaultFn(() => createId()),
  ...timestampsSchema,
}

export const providerSchema = {
  provider_name: customEnum<Providers>('provider_name').notNull(),
  provider_title: t.text().notNull(),
  provider_command: t.text().notNull(),
  provider_args: t.text({ mode: 'json' }).$type<string[]>().notNull(),
}

export enum SessionStatus {
  active = 'active',
  completed = 'completed',
  suspended = 'suspended',
  error = 'error',
}
export const sessionStatusSchema = {
  status: customEnum<SessionStatus>('status')
    .notNull()
    .default(SessionStatus.active),
}

export enum MessageRole {
  user = 'user',
  assistant = 'assistant',
  system = 'system',
}

export const messageRoleSchema = {
  role: customEnum<MessageRole>('role').notNull(),
}
