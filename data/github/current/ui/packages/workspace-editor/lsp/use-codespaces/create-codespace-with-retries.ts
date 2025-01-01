import {reactFetchJSON} from '@github-ui/verified-fetch'

import {AssertionError, HttpError} from '../../errors'
import {assert, assertValidCodespaceInfo} from '../../utilities/asserts'
import {type IWithRetriesOptions, withRetries} from '../../utilities/with-retries'
import {
  type CodespaceErrorResponse,
  type CodespaceInfoBase,
  type CodespaceInfoExtended,
  CodespaceStateInfo,
} from '../../utilities/workspace-editor-types'

// Create a new Codespace with provided service URL.
export const createCodespaceWithRetries = async (
  url: string,
  force: boolean,
  retryOptions: Partial<IWithRetriesOptions>,
): Promise<CodespaceInfoExtended> => {
  return await withRetries(
    async () => {
      const response = await reactFetchJSON(url, {body: {force_create: force}, method: 'POST'})
      if (!response.ok) {
        const data: CodespaceErrorResponse = await response.json()
        throw new AssertionError(data.error ?? `${response.status} - ${response.statusText}`)
      }

      const data: CodespaceInfoBase | object = await response.json()
      assertValidCodespaceInfo(data, 'Failed to create codespace')

      assert(data.environment_data.state !== CodespaceStateInfo.Failed, 'Codespace is in the failed state.')
      const isReconnect = response.status === 200
      return {data, isReconnect}
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
