/**
 * Utility function to wrap any async function in a try-catch block.
 * Logs any errors that occur and rethrows them.
 */

import type { ICommsInterface } from 'src/comms/ICommsInterface'
import { logError, logTraffic } from './logger'
import type { Stream } from '@agentclientprotocol/sdk'

export function generateCatchblock(
  commsInterface: ICommsInterface | null,
  error: unknown,
  failureMessage: string | null,
) {
  const errObj = error as Error
  const failMessage =
    failureMessage ??
    `Error thrown in ${generateCatchblock.caller?.name || 'unknown function'}`
  logError(failMessage, errObj)
  commsInterface?.notify({
    method: 'agentic/log',
    data: {
      level: 'error',
      message: `${failMessage}: ${errObj.message || String(errObj)}`,
    },
  })
}

export function tapStream(stream: Stream): Stream {
  const sendTap = new TransformStream({
    transform(chunk: unknown, controller: TransformStreamDefaultController) {
      logTraffic('send', '', chunk)
      controller.enqueue(chunk)
    },
  })

  const receiveTap = new TransformStream({
    transform(chunk: unknown, controller: TransformStreamDefaultController) {
      logTraffic('receive', '', chunk)
      controller.enqueue(chunk)
    },
  })

  sendTap.readable.pipeTo(stream.writable).catch((err) => {
    logError('Error piping sendTap', err)
  })
  stream.readable.pipeTo(receiveTap.writable).catch((err) => {
    logError('Error piping receiveTap', err)
  })

  return {
    readable: receiveTap.readable,
    writable: sendTap.writable,
  }
}
