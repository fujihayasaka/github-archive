import {useMutation, useQueryClient} from '@github-ui/react-query'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {useMergeBoxPageDataQueryKey} from '../../page-data/loaders/use-merge-box-page-data'
import {
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
  parseJSONWithBetterErrors,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'

type Callbacks = {
  onError: (error: Error) => void
}

export function useDequeuePullRequestMutation({onError}: Callbacks) {
  const apiURL = usePageDataUrl(PageData.dequeuePullRequest)
  const mergeBoxQueryKey = useMergeBoxPageDataQueryKey()
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
      return queryClient.invalidateQueries({queryKey: mergeBoxQueryKey}, {cancelRefetch: false})
    },
    onError: (e: Error) => {
      onError(e)
    },
  })
}
