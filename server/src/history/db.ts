import { Database } from "bun:sqlite";
import { join } from "path";
import { homedir } from "os";
import { mkdirSync } from "fs";

// Store the db in the plugin's data directory globally
const DATA_DIR = join(homedir(), ".local", "share", "nvim", "agentic");
try {
  mkdirSync(DATA_DIR, { recursive: true });
} catch (e) {}

const DB_PATH = join(DATA_DIR, "history.sqlite");

export const db = new Database(DB_PATH);

// Initialize tables
db.run(`
    CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        provider TEXT NOT NULL,
        name TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
`);

db.run(`
    CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL, -- 'user', 'assistant', 'system'
        content TEXT NOT NULL,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
    )
`);

export interface Session {
  id: string;
  provider: string;
  name: string | null;
  created_at: string;
  updated_at: string;
}

export interface Message {
  id: number;
  session_id: string;
  role: "user" | "assistant" | "system";
  content: string;
  timestamp: string;
}

export function createSession(
  id: string,
  provider: string,
  name?: string,
): Session {
  db.run("INSERT INTO sessions (id, provider, name) VALUES (?, ?, ?)", [
    id,
    provider,
    name || null,
  ]);
  return getSession(id) as Session;
}

export function getSession(id: string): Session | null {
  return db
    .query("SELECT * FROM sessions WHERE id = ?")
    .get(id) as Session | null;
}

export function addMessage(sessionId: string, role: string, content: string) {
  db.run("INSERT INTO messages (session_id, role, content) VALUES (?, ?, ?)", [
    sessionId,
    role,
    content,
  ]);

  // Update session timestamp
  db.run("UPDATE sessions SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", [
    sessionId,
  ]);
}

export function getMessages(sessionId: string): Message[] {
  return db
    .query("SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp ASC")
    .all(sessionId) as Message[];
}
