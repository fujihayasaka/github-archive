import {reactFetchJSON} from '@github-ui/verified-fetch'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {useMergeBoxPageDataQueryKey} from '../../page-data/loaders/use-merge-box-page-data'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
  parseJSONWithBetterErrors,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'

export function useCleanupCodespacesMutation({onError}: {onError: (error: Error) => void}) {
  const apiURL = usePageDataUrl(PageData.cleanupCodespaces)
  const mergeBoxQueryKey = useMergeBoxPageDataQueryKey()
  const queryClient = useQueryClient()
  const useFetchWithErrorHandling = useFeatureFlag('merge_box_use_fetch_with_error_handling')

  return useMutation({
    mutationFn: async () => {
      if (useFetchWithErrorHandling) {
        const response = await fetchWithErrorHandling(apiURL, {
          method: 'POST',
          headers: {
            Accept: 'application/json',
          },
        })
        const json = await parseJSONWithBetterErrors(response)
        throwErrorsIfBadResponse(response, json)
        return json
      } else {
        const result = await reactFetchJSON(`${apiURL}`, {
          method: 'POST',
          headers: {
            Accept: 'application/json',
          },
        })
        const json = await result.json()
        if (result.ok) return json
        const errorMessage = json.error || 'Unknown error occurred'
        throw new Error(errorMessage, {cause: result.status})
      }
    },
    onSuccess: () => {
      return queryClient.invalidateQueries({queryKey: mergeBoxQueryKey}, {cancelRefetch: false})
    },
    onError: (e: Error) => {
      onError(e)
    },
  })
}
