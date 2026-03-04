CREATE TABLE `agents` (
	`id` text PRIMARY KEY,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	`provider_name` text NOT NULL,
	`provider_title` text NOT NULL,
	`provider_command` text NOT NULL,
	`provider_args` text NOT NULL,
	`permissions_rule` text DEFAULT 'ask' NOT NULL,
	`cwd` text NOT NULL,
	`env` text
);
--> statement-breakpoint
CREATE TABLE `messages` (
	`id` text PRIMARY KEY,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	`role` text NOT NULL,
	`content` text NOT NULL,
	`session_id` text NOT NULL,
	CONSTRAINT `fk_messages_session_id_sessions_id_fk` FOREIGN KEY (`session_id`) REFERENCES `sessions`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE `session_summaries` (
	`id` text PRIMARY KEY,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	`session_id` text NOT NULL,
	`summary` text NOT NULL,
	CONSTRAINT `fk_session_summaries_session_id_sessions_id_fk` FOREIGN KEY (`session_id`) REFERENCES `sessions`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE `sessions` (
	`id` text PRIMARY KEY,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	`status` text DEFAULT 'active' NOT NULL,
	`name` text,
	`agent_id` text NOT NULL,
	`summary_generated` integer DEFAULT false,
	CONSTRAINT `fk_sessions_agent_id_agents_id_fk` FOREIGN KEY (`agent_id`) REFERENCES `agents`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE INDEX `idx_agent_provider_cwd` ON `agents` (`provider_name`,`cwd`);--> statement-breakpoint
CREATE INDEX `idx_agent_created_at` ON `agents` (`created_at`);--> statement-breakpoint
CREATE INDEX `idx_agent_updated_at` ON `agents` (`updated_at`);--> statement-breakpoint
CREATE INDEX `idx_message_session_id` ON `messages` (`session_id`);--> statement-breakpoint
CREATE INDEX `idx_message_role` ON `messages` (`role`);--> statement-breakpoint
CREATE INDEX `idx_message_created_at` ON `messages` (`created_at`);--> statement-breakpoint
CREATE INDEX `idx_message_updated_at` ON `messages` (`updated_at`);--> statement-breakpoint
CREATE INDEX `idx_session_summary_session_id` ON `session_summaries` (`session_id`);--> statement-breakpoint
CREATE INDEX `idx_session_summary_created_at` ON `session_summaries` (`created_at`);--> statement-breakpoint
CREATE INDEX `idx_session_summary_updated_at` ON `session_summaries` (`updated_at`);--> statement-breakpoint
CREATE INDEX `idx_session_agent_id` ON `sessions` (`agent_id`);--> statement-breakpoint
CREATE INDEX `idx_session_created_at` ON `sessions` (`created_at`);--> statement-breakpoint
CREATE INDEX `idx_session_updated_at` ON `sessions` (`updated_at`);