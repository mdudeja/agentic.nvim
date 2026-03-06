# agentic.nvim — Server

The server is a **TypeScript/Bun** backend that bridges the Neovim plugin with AI coding agents (GitHub Copilot, OpenCode, Gemini). It communicates with Neovim over JSON-RPC and with the agents over the **Agent-Client Protocol (ACP)**.

---

## Table of Contents

- [Overview](#overview)
- [Startup Modes](#startup-modes)
- [Directory Structure](#directory-structure)
- [Architecture](#architecture)
  - [Entry Point](#entry-point)
  - [Communication Layer](#communication-layer)
  - [Agent-Client Protocol (ACP)](#agent-client-protocol-acp)
  - [Managers](#managers)
  - [Database](#database)
  - [OpenRPC / Schema Layer](#openrpc--schema-layer)
  - [State](#state)
  - [Data & Events](#data--events)
  - [Context Ingestion](#context-ingestion)
  - [Utilities](#utilities)
- [JSON-RPC API](#json-rpc-api)
  - [Client → Server Methods](#client--server-methods)
  - [Server → Client Notifications](#server--client-notifications)
- [Supported AI Providers](#supported-ai-providers)
- [Database Schema](#database-schema)
- [What Is Working](#what-is-working)
- [What Is In Progress / TODO](#what-is-in-progress--todo)
- [Environment Variables](#environment-variables)
- [Running the Server](#running-the-server)

---

## Overview

```
Neovim plugin <──JSON-RPC──> AgenticServer <──ACP (stdio/NDJSON)──> AI Agent process
                                   │
                              SQLite (Drizzle)
```

The server sits in the middle:

- **Neovim side**: receives commands (init, ask, terminal responses) and sends notifications (logs, terminal requests, questions).
- **Agent side**: spawns the AI agent process, establishes an ACP `ClientSideConnection` over the process's stdin/stdout, and acts as the ACP client (file system, terminal, permission operations are delegated back to Neovim).

---

## Startup Modes

| Mode | How to trigger | Transport |
|------|---------------|-----------|
| **RPC** (default) | `bun run index.ts` | stdin / stdout, newline-delimited JSON |
| **HTTP/WebSocket** | `bun run index.ts --http` or `APP_MODE=server` | WebSocket at `ws://localhost:<port>/ws`; also serves `/openrpc.json` and `/docs` |

The `ReadlineCommsInterface` handles RPC mode; `WebsocketCommsInterface` handles HTTP mode.

---

## Directory Structure

```
server/
├── index.ts                     # Entry point – mode detection, server bootstrap
├── main.ts                      # AgenticServer class – core orchestrator
├── src/
│   ├── acp/
│   │   ├── Client.ts            # AcpClient — ACP Client implementation
│   │   └── handlers/
│   │       ├── FileSystemHandler.ts    # Read / write text files
│   │       ├── PermissionHandler.ts   # Grant / deny / prompt permissions
│   │       └── TerminalHandler.ts     # Full terminal lifecycle via Neovim
│   ├── comms/
│   │   ├── ICommsInterface.ts         # Contract + shared RPC types
│   │   ├── ReadlineCommsInterface.ts  # stdin/stdout JSON-RPC
│   │   └── WebsocketCommsInterface.ts # WebSocket JSON-RPC + docs server
│   ├── data/
│   │   ├── events.ts            # Typed event maps for all managers
│   │   └── providers.ts         # Supported AI provider configs
│   ├── database/
│   │   ├── AgenticDB.ts         # Singleton SQLite/Drizzle wrapper + migrations
│   │   ├── validation.ts
│   │   └── schemas/
│   │       ├── common.schema.ts        # Shared column sets + enums
│   │       ├── agents.schema.ts
│   │       ├── sessions.schema.ts
│   │       ├── messages.schema.ts
│   │       ├── session_summaries.schema.ts
│   │       └── index.ts
│   ├── ingester/
│   │   └── index.ts             # ContextIngester – prompt synthesis (not yet active)
│   ├── managers/
│   │   ├── BaseManager.ts       # Typed EventEmitter base class
│   │   ├── AgentManager.ts      # Agent lifecycle (create → spawn → connect → kill)
│   │   ├── SessionManager.ts    # Session CRUD + ACP session coordination
│   │   ├── MessageManager.ts    # Save/retrieve prompts and responses
│   │   └── SessionSummaryManager.ts   # Post-session summarization (stub)
│   ├── openrpc/
│   │   ├── schemas.ts           # TypeBox schemas — single source of truth
│   │   ├── spec.ts              # OpenRPC spec builder
│   │   ├── types.ts             # Minimal OpenRPC TypeScript types
│   │   └── openrpc.json         # Generated spec (do not edit manually)
│   ├── state/
│   │   ├── IASMState.ts         # ASMState type + IASMState interface
│   │   └── index.ts             # ASMStateManager implementation
│   └── utils/
│       ├── datetime.ts          # Timestamp helpers
│       ├── helpers.ts           # generateCatchblock, tapStream
│       ├── logger.ts            # Structured logger (level-filtered)
│       ├── paths.ts             # Path resolution relative to CWD / env
│       ├── renderopenrpcdocs.ts # Renders HTML docs from OpenRPC spec
│       └── shell.ts             # spawnShellCommand
├── scripts/
│   └── gen-openrpc.ts           # Regenerates openrpc.json from spec.ts
└── drizzle_migrations/          # Drizzle migration files
```

---

## Architecture

### Entry Point

**`index.ts`** — reads CLI flags (`--http`, `--port=<n>`) and environment variables (`APP_MODE`, `HTTP_PORT`) to determine mode and port. Creates and starts `AgenticServer`, wires `SIGINT` for graceful shutdown.

**`main.ts` — `AgenticServer`** — the central orchestrator:

1. Creates `ASMStateManager` (in-memory runtime state).
2. Creates the appropriate `ICommsInterface` implementation.
3. On `init()`, registers `onMessage` and `onClose` handlers and starts the comms interface.
4. Parses and validates every incoming message against `ASMPayloadSchema` (TypeBox + typebox/value `Check()`).
5. Dispatches to private handlers (`_initAgentManager`, `_initSessionManager`, etc.) and wires up event listeners on the managers.

### Communication Layer

All comms are JSON-RPC 2.0 style messages with a `method` and `data` field.

| Class | Description |
|-------|-------------|
| `ICommsInterface` | Contract: `init`, `onMessage`, `onClose`, `respond`, `notify`, `question`, `dispose` |
| `ReadlineCommsInterface` | Uses Node's `readline/promises` over `process.stdin` / `process.stdout`. One message per line. |
| `WebsocketCommsInterface` | Bun WebSocket server. Also exposes `GET /openrpc.json` and `GET /docs`. Handles `client/answer` messages internally for interactive questions. |

### Agent-Client Protocol (ACP)

The ACP SDK (`@agentclientprotocol/sdk`) defines the protocol between an AI agent (server-side) and a client (us). The server implements the **client** role.

**`AcpClient`** implements `acp.Client`. Every ACP capability (file system, terminal, permissions) is delegated to a dedicated handler:

| Handler | ACP capability | What it does |
|---------|---------------|--------------|
| `FileSystemHandler` | `readTextFile`, `writeTextFile` | Direct `fs` operations with optional line-range support and auto `mkdir` |
| `PermissionHandler` | `requestPermission` | Checks the agent's `permissions_rule`; auto-grants if `allow`, auto-denies if `deny`, otherwise sends `agentic/question` to Neovim and waits |
| `TerminalHandler` | `createTerminal`, `terminalOutput`, `waitForTerminalExit`, `killTerminal`, `releaseTerminal` | Sends `agentic/terminal` notifications to Neovim and resolves a promise when the corresponding `client/terminal` response arrives back; tracks terminals in a local `Map` with per-operation timeouts |

### Managers

All managers extend `BaseManager<T>` which is a typed wrapper around Node's `EventEmitter`.

#### `AgentManager`

Lifecycle: **init → spawn → connect**

1. **`init()`** — queries the database for an existing agent matching `(provider, cwd)`. If none exists, inserts a new record and emits `agent.created`. Emits `agent.loaded` either way.
2. **`spawn()`** — calls `spawnShellCommand` (via `Bun.spawn`) with the provider's CLI command (e.g., `copilot --acp`). Emits `agent.spawned`.
3. **`connect()`** — wraps the spawned process's stdio as Web Streams, creates an `ndJsonStream`, builds `AcpClient` + `ClientSideConnection`, calls `connection.initialize()` with declared capabilities (`fs.readTextFile`, `fs.writeTextFile`, `terminal`), then emits `agent.connected`. Listens for `connection.closed` to emit `agent.disconnected`.
4. **`handleTerminalResponse()`** — proxies `client/terminal` payloads from Neovim to `TerminalHandler.handleResponse()`.
5. **`kill()`** — sends `SIGKILL` to the process and emits `agent.killed`.

Event flow wired in `AgenticServer`:

```
client/init received
  → AgentManager.init()
      → agent.loaded  → AgentManager.spawn()
      → agent.spawned → AgentManager.connect()
      → agent.connected → SessionManager.init()
```

#### `SessionManager`

Manages ACP sessions scoped to the active agent:

- **`init()`** — loads all existing sessions for the current agent from the database and stores the ACP connection from state.
- **`createNewSession()`** — calls `connection.csc.newSession()` (ACP), inserts a `sessions` row, sets it as active.
- **`closeCurrentSession()`** — marks session `completed`.
- CRUD helpers: `renameSession`, `deleteSession`, `archiveSession`, `updateSession`.

### Database

**SQLite via Drizzle ORM, running on `bun:sqlite`.**

`AgenticDB` is a singleton initialized lazily on first `getDB()` call. It:
- Creates the DB file and parent directory if needed.
- Enables `PRAGMA foreign_keys`, WAL journal mode, `NORMAL` synchronous writes.
- Runs Drizzle migrations from `drizzle_migrations/`.
- Defines relations (`agents → sessions → messages → session_summaries`).

### OpenRPC / Schema Layer

TypeBox schemas in `src/openrpc/schemas.ts` are the **single source of truth** for:

1. **TypeScript types** — via `Static<typeof SomeSchema>`.
2. **Runtime validation** — incoming messages are validated with `Check(ASMPayloadSchema, raw)` before processing.
3. **OpenRPC spec** — `spec.ts` builds the full OpenRPC document from the TypeBox schemas; `scripts/gen-openrpc.ts` writes it to `openrpc.json`.

The WebSocket server serves this spec at `/openrpc.json` and an HTML docs page at `/docs`.

### State

`ASMStateManager` is a simple in-memory key-value store typed to `ASMState`:

```typescript
type ASMState = {
  agent?:      Agent['Select'] & { process?: Subprocess }
  session?:    Session['Select'] & {configOptions?: SessionConfigOption[]; models?: SessionModelState; modes?: SessionModeState }
  connection?: { csc: ClientSideConnection; client: AcpClient; initResponse: InitializeResponse }
}
```

Managers read state via `server_instance.getState()`.

### Data & Events

**`providers.ts`** — three providers with their CLI binaries and ACP flags:

| Key | Binary | ACP flag |
|-----|--------|----------|
| `copilot` | `copilot` | `--acp` |
| `opencode` | `opencode` | `acp` |
| `gemini` | `gemini` | `--experimental-acp` |

**`events.ts`** — typed event maps (`AgentEvents`, `SessionEvents`, `MessageEvents`, `SummaryEvents`) that parameterise `BaseManager`.

### Context Ingestion

`ContextIngester` (in `src/ingester/`) takes a user's prompt and an array of `NeovimContext` payloads (selection, file, workspace, keymaps, diagnostics) and assembles them into a structured prompt string. It avoids redundant injection (e.g., skips keymaps if already present in session history).

> **Not yet wired in** — the `client/ask` handler in `main.ts` is commented out.

### Utilities

| File | Purpose |
|------|---------|
| `logger.ts` | Levelled logging; respects `LOG_LEVEL` env var |
| `paths.ts` | `resolvePath` — resolves paths relative to `process.cwd()` or an env base |
| `datetime.ts` | `getNowMillis()` for DB timestamps |
| `helpers.ts` | `generateCatchblock` (error → JSON-RPC error response), `tapStream` (logs NDJSON traffic) |
| `shell.ts` | `spawnShellCommand` — thin wrapper around `Bun.spawn` |
| `renderopenrpcdocs.ts` | Generates an inline HTML page from an OpenRPC spec |

---

## JSON-RPC API

Messages follow this envelope:

```json
{ "jsonrpc": "2.0", "data": { "method": "...", "params": { ... } } }
```

### Client → Server Methods

| Method | Params | Description |
|--------|--------|-------------|
| `client/init` | `{ provider, cwd, sessionName? }` | Look up or create the agent, spawn its process, connect ACP, init the session manager |
| `client/dispose` | `{ reason?, agentId? }` | Gracefully shut down the server |
| `client/ask` | `{ prompt, contexts? }` | *(In progress)* Send a prompt to the active agent |
| `client/get_history` | `{ sessionId }` | *(Stub)* Retrieve message history for a session |
| `client/terminal` | Terminal response payload | Forward a terminal operation result from Neovim back to `TerminalHandler` |
| `client/answer` | `{ questionId, answer }` | Answer a pending `agentic/question` (WebSocket mode — handled by `WebsocketCommsInterface`) |

### Server → Client Notifications

| Method | Payload | Description |
|--------|---------|-------------|
| `agentic/log` | `{ level, message }` | Send a log message to Neovim |
| `agentic/terminal` | Terminal request payload | Ask Neovim to perform a terminal operation |
| `agentic/question` | `{ questionId, question }` | Ask the user a question (e.g., permission prompt) |

---

## Supported AI Providers

| Provider | CLI command | ACP flag |
|----------|-------------|----------|
| GitHub Copilot | `copilot` | `--acp` |
| OpenCode | `opencode` | `acp` |
| Gemini | `gemini` | `--experimental-acp` |

---

## Database Schema

```
agents
  id (cuid2 PK), provider_name, provider_title, provider_command, provider_args,
  permissions_rule (allow|deny|ask), cwd, env, created_at, updated_at

sessions
  id, agent_id → agents, acp_session_id, name,
  status (active|completed|archived|error),
  is_archived, created_at, updated_at
```

Relations: `agents` → many `sessions`

---

## What Is Working

- Dual-mode startup (RPC stdin/stdout and WebSocket)
- Incoming message validation with TypeBox schemas
- Agent lookup / creation in the database
- Agent process spawning (`copilot --acp`, etc.)
- ACP `ClientSideConnection` initialization over process stdio (NDJSON)
- File system operations (`readTextFile`, `writeTextFile`) with line-range support
- Permission handling — auto-grant, auto-deny, and interactive user prompts
- Full terminal lifecycle in Neovim: create, get_output, wait_exit, kill, release — with per-operation timeouts and promise-based request/response tracking
- Session loading and new session creation via ACP
- Session CRUD (rename, delete, archive, status update)
- Message persistence (prompt + response as `ContentBlock[]`)
- SQLite database with Drizzle ORM, WAL mode, automatic migrations
- OpenRPC spec generation and HTML docs endpoint (WebSocket mode)

---

## What Is In Progress / TODO

| Area | Status |
|------|--------|
| `client/ask` prompt flow | Handler commented out in `main.ts` — needs wiring to `SessionManager`, `MessageManager`, `ContextIngester`, and ACP `prompt()` |
| `client/get_history` | Stub — `MessageManager.getAllForSession` exists but response is not sent yet |
| `SessionSummaryManager.createSummary` | Fetches messages but summarization logic is not implemented |
| `ContextIngester` | Complete but not connected to the ask flow |
| `SessionManager.launchSession` | Empty method body |
| Agent stdout/stderr streaming | `spawn()` has commented-out stream-reading loops for monitoring agent output directly |

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_MODE` | `rpc` | Set to `server` for WebSocket/HTTP mode |
| `HTTP_PORT` | `3777` | WebSocket server port (HTTP mode only) |
| `LOG_LEVEL` | `info` | Logger verbosity |
| `LOG_TRAFFIC` | `false` | Log raw NDJSON traffic to/from the agent process |
| `DB_FILE_URL` | *(required)* | Path to the SQLite database file |
| `DB_MIGRATIONS_DIR` | `./drizzle_migrations` | Path to Drizzle migration files |
| `OPENRPC_SCHEMA_PATH` | `src/openrpc/openrpc.json` | Path to the generated OpenRPC spec |

---

## Running the Server

```bash
# Install dependencies
bun install

# RPC mode (used by the Neovim plugin via stdio)
bun run start

# WebSocket / HTTP mode (for development / testing)
bun run start:http

# Regenerate OpenRPC spec
bun run gen:openrpc

# Type-check
bun run lint
```
