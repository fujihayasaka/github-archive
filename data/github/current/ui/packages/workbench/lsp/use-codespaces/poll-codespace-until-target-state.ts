import {reactFetchJSON} from '@github-ui/verified-fetch'
import {AssertionError, HttpError} from '@github-ui/workspace-editor/errors'
import {CodespaceError, CodespaceNotInTargetStateError} from '@github-ui/workspace-editor/errors/codespace-error'
import {assert, assertValidCodespaceInfo} from '@github-ui/workspace-editor/utilities/asserts'
import {type IWithRetriesOptions, withRetries} from '@github-ui/workspace-editor/utilities/with-retries'
import {
  type CodespaceErrorResponse,
  type CodespaceInfoBase,
  CodespaceStateInfo,
} from '@github-ui/workspace-editor/utilities/workspace-editor-types'

const CODESPACE_STOP_POLLING_STATES = new Set<CodespaceStateInfo>([
  CodespaceStateInfo.Deleted,
  CodespaceStateInfo.Failed,
  CodespaceStateInfo.Unavailable,
])

/**
 * Refreshes existing codespace info using the provided service URL.
 */
export const pollCodespaceUntilTargetState = async (
  url: string,
  targetState: CodespaceStateInfo,
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
        newInfo.environment_data.state === targetState,
        new CodespaceNotInTargetStateError(targetState, newInfo.environment_data.state),
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
          return CODESPACE_STOP_POLLING_STATES.has(error.codespaceState)
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
