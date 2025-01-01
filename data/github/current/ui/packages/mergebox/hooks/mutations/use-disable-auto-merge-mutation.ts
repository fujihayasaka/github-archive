import {useMutation, useQueryClient} from '@github-ui/react-query'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {useMergeBoxPageDataQueryKey} from '../../page-data/loaders/use-merge-box-page-data'
import {
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
  parseJSONWithBetterErrors,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'

export function useDisableAutoMergeMutation({onError}: {onError: (error: Error) => void}) {
  const apiURL = usePageDataUrl(PageData.disableAutoMerge)
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
      return queryClient.refetchQueries({queryKey: mergeBoxQueryKey}, {cancelRefetch: false})
    },
    onError: (e: Error) => {
      onError(e)
    },
  })
}
