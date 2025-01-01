import {reactFetchJSON} from '@github-ui/verified-fetch'
import {AssertionError, HttpError} from '@github-ui/workspace-editor/errors'
import {assertValidCodespaceInfo} from '@github-ui/workspace-editor/utilities/asserts'
import {type IWithRetriesOptions, withRetries} from '@github-ui/workspace-editor/utilities/with-retries'
import type {
  CodespaceErrorResponse,
  CodespaceInfoBase,
} from '@github-ui/workspace-editor/utilities/workspace-editor-types'

// Starts a codespace with provided service URL.
export const startCodespaceWithRetries = async (
  url: string,
  retryOptions: Partial<IWithRetriesOptions>,
): Promise<CodespaceInfoBase> => {
  return await withRetries(
    async () => {
      const response = await reactFetchJSON(url, {body: {}, method: 'POST'})
      if (!response.ok) {
        const data: CodespaceErrorResponse = await response.json()
        throw new AssertionError(data.error ?? `${response.status} - ${response.statusText}`)
      }

      const data: CodespaceInfoBase | object = await response.json()
      assertValidCodespaceInfo(data, 'Failed to start codespace')

      return data
    },
    {
      ...retryOptions,
      retries: retryOptions.retries ?? 3,
      retryDelayMs: retryOptions.retryDelayMs ?? 1000,
      shouldStopRetries: (error, retriesLeft) => {
        // if a custom `shouldStopRetries` function is provided, use it
        if (typeof retryOptions.shouldStopRetries === 'function') {
          return retryOptions.shouldStopRetries(error, retriesLeft)
        }

        // continue retrying unless the error is fatal
        return error instanceof HttpError && !error.isRetriable()
      },
    },
  )
}
