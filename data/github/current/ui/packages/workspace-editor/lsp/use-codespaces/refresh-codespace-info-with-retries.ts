import {reactFetchJSON} from '@github-ui/verified-fetch'

import {AssertionError, HttpError} from '../../errors'
import {CodespaceError} from '../../errors/codespace-error'
import {assert, assertValidCodespaceInfo} from '../../utilities/asserts'
import {type IWithRetriesOptions, withRetries} from '../../utilities/with-retries'
import {
  type CodespaceErrorResponse,
  type CodespaceInfoBase,
  CodespaceStateInfo,
} from '../../utilities/workspace-editor-types'

// We shouldn't ever see the deleted, shutdown, or shutting down states, but we're including them for safety
const CODESPACE_STOP_POLLING_STATES = [
  CodespaceStateInfo.Deleted,
  CodespaceStateInfo.Failed,
  CodespaceStateInfo.Shutdown,
  CodespaceStateInfo.ShuttingDown,
  CodespaceStateInfo.Unavailable,
]

/**
 * Refreshes existing codespace info using the provided service URL.
 */
export const refreshCodespaceInfoWithRetries = async (
  url: string,
  retryOptions: Partial<IWithRetriesOptions>,
): Promise<CodespaceInfoBase> => {
  return await withRetries(
    async () => {
      const response = await reactFetchJSON(url, {})
      assert(response.ok, HttpError.fromResponse(response, 'Request to refresh codespace info failed'))
      if (!response.ok) {
        const data: CodespaceErrorResponse = await response.json()
        throw new AssertionError(data.error ?? `${response.status} - ${response.statusText}`)
      }

      const newInfo: CodespaceInfoBase | object = await response.json()
      assertValidCodespaceInfo(newInfo, 'Failed to refresh codespace info')

      assert(
        newInfo.environment_data.state !== CodespaceStateInfo.Failed,
        new CodespaceError('Codespace is in the failed state.', newInfo.environment_data.state),
      )

      assert(
        newInfo.environment_data.state === CodespaceStateInfo.Available,
        new CodespaceError('Codespace is not available.', newInfo.environment_data.state),
      )

      return newInfo
    },
    {
      ...retryOptions,
      retries: retryOptions.retries ?? Infinity,
      retryDelayMs: retryOptions.retryDelayMs ?? 1000,
      exponentialBackoffFactor: retryOptions.exponentialBackoffFactor ?? 1.02,
      shouldStopRetries: (error, retriesLeft) => {
        // if a custom `shouldStopRetries` function is provided, use it
        if (typeof retryOptions.shouldStopRetries === 'function') {
          return retryOptions.shouldStopRetries(error, retriesLeft)
        }

        // if Codespace is in the failed state, we should stop the retries
        if (error instanceof CodespaceError && error.codespaceState) {
          return CODESPACE_STOP_POLLING_STATES.includes(error.codespaceState)
        }

        // if HTTP error is not retriable, we should stop the retries
        if (error instanceof HttpError) {
          return !error.isRetriable()
        }

        return false
      },
    },
  )
}
