/**
 * Utility function to wrap any async function in a try-catch block.
 * Logs any errors that occur and rethrows them.
 */

import type { ICommsInterface } from 'src/comms/ICommsInterface'
import { logError } from './logger'

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
