// Helper to send JSON-RPC responses back to Neovim
export function respond(id: string | number, result: any, error?: any) {
  process.stdout.write(
    JSON.stringify({
      jsonrpc: '2.0',
      id,
      result: error ? undefined : result,
      error: error
        ? { code: -32000, message: error.message || String(error) }
        : undefined,
    }) + '\n',
  )
}

// Helper to send server push notifications back to Neovim
export function notify(method: string, params: any) {
  process.stdout.write(
    JSON.stringify({
      jsonrpc: '2.0',
      method,
      params,
    }) + '\n',
  )
}
