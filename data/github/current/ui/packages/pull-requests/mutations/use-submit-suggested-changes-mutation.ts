import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {
  parseJSONWithBetterErrors,
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {useMutation} from '@github-ui/react-query'
import type {SuggestedChange} from '@github-ui/conversations'
import {ssrSafeWindow} from '@github-ui/ssr-utils'

/**
 * Applies a single suggested change
 */
export function useSubmitSuggestedChangesMutation(basePath: string) {
  const apiUrl = `${basePath}/page_data/${PageData.submitSuggestedChanges}`

  return useMutation({
    mutationFn: async ({
      changes,
      currentOid,
      message,
    }: {
      changes: SuggestedChange[]
      currentOid: string
      message: string
    }) => {
      const response = await fetchWithErrorHandling(apiUrl, {
        method: 'POST',
        body: {
          changes,
          currentOid,
          message,
        },
      })

      const json = await parseJSONWithBetterErrors(response)
      throwErrorsIfBadResponse(response, json)
      return json
    },
    onSuccess: () => {
      //we want to reload so we get the updated diff
      ssrSafeWindow?.location.reload()
    },
  })
}
