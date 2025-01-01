import {useMutation, useQueryClient} from '@github-ui/react-query'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
  parseJSONWithBetterErrors,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'

import {useStatusChecksPageDataQueryKey} from '../../page-data/loaders/use-status-checks-page-data'

export function useRunActionRequiredWorkflows({pullRequestHeadSha}: {pullRequestHeadSha: string}) {
  const apiURL = usePageDataUrl(PageData.runActionRequiredWorkflows)
  const statusChecksQueryKey = useStatusChecksPageDataQueryKey({pullRequestHeadSha})
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async () => {
      const response = await fetchWithErrorHandling(apiURL, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
        },
      })
      const json = await parseJSONWithBetterErrors(response)
      throwErrorsIfBadResponse(response, json)
      return json
    },
    onSuccess: () => {
      return queryClient.invalidateQueries({queryKey: statusChecksQueryKey}, {cancelRefetch: false})
    },
  })
}
