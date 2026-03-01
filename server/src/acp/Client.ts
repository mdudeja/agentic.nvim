import * as acp from '@agentclientprotocol/sdk'
import type { InitializeResponse } from '@agentclientprotocol/sdk'
import { spawn, type ChildProcess } from 'child_process'
import { Readable, Writable } from 'node:stream'
import type { PROVIDERS } from 'src/data/providers'

export type ProviderConfig = (typeof PROVIDERS)[keyof typeof PROVIDERS]

export class ProviderClient implements acp.Client {
  private config: ProviderConfig
  private connection: acp.ClientSideConnection | null = null
  private process: ChildProcess | null = null

  public onSessionUpdate?: (text: string) => void

  constructor(name: keyof typeof PROVIDERS) {
    this.config = PROVIDERS[name]
  }

  public async connect(): Promise<acp.InitializeResponse> {
    console.log(
      `[Provider] Spawning ${this.config.name} via ${this.config.command} ${this.config.args.join(' ')}`,
    )

    this.process = spawn(this.config.command, this.config.args, {
      env: process.env,
      stdio: ['pipe', 'pipe', 'inherit'], // stdin, stdout, stderr (passed to host)
    })

    if (!this.process.stdout || !this.process.stdin) {
      throw new Error(`Failed to establish stdio for ${this.config.name}`)
    }

    // Bind ACP Streams (Converting Node Streams to Web Streams for the SDK)
    const webStdout = Readable.toWeb(
      this.process.stdout,
    ) as unknown as ReadableStream<Uint8Array>
    const webStdin = Writable.toWeb(
      this.process.stdin,
    ) as unknown as WritableStream<Uint8Array>
    const stream = ndJsonStream(webStdout, webStdin)

    // Instantiate ACP Connection passing the Client handler scaffold
    const _this = this
    this.connection = new ClientSideConnection((agent) => {
      return {
        async sessionUpdate(params: any) {
          if (params.update?.sessionUpdate === 'agent_message_chunk') {
            const content = params.update.content
            if (content?.type === 'text' && content.text) {
              if (_this.onSessionUpdate) {
                _this.onSessionUpdate(content.text)
              }
            }
          }
        },
        async requestPermission() {
          return { outcome: { outcome: 'cancelled' } } as any
        },
      } as any
    }, stream)

    // Initialize ACP Handshake
    const capabilities = await this.connection.initialize({
      clientInfo: {
        name: 'agentic.nvim',
        version: '1.0.0',
      },
      protocolVersion: 1,
    })

    console.log(
      `[Provider] Initialized ${this.config.name} over ACP. Options:`,
      capabilities,
    )
    return capabilities
  }

  public async disconnect(): Promise<void> {
    if (this.process) {
      this.process.kill()
      this.process = null
    }
    this.connection = null
  }

  public getConnection(): ClientSideConnection {
    if (!this.connection) {
      throw new Error('Connection not established')
    }
    return this.connection
  }
}
