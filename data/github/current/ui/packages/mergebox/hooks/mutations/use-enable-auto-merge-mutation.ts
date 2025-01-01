import {useMutation, useQueryClient} from '@github-ui/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {useMergeBoxPageDataQueryKey} from '../../page-data/loaders/use-merge-box-page-data'
import {MergeError} from '../../helpers/merge-error'
import {
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
  parseJSONWithBetterErrors,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

type EnableAutoMergeInput = {
  authorEmail?: string | null
  commitMessage?: string | null | undefined
  commitTitle?: string | null | undefined
  mergeMethod?: string
}

type Callbacks = {
  onError?: (error: Error) => void
  onSuccess?: () => void
}
export function useEnableAutoMergeMutation({onError, onSuccess}: Callbacks = {}) {
  const apiURL = usePageDataUrl(PageData.enableAutoMerge)
  const mergeBoxQueryKey = useMergeBoxPageDataQueryKey()
  const queryClient = useQueryClient()
  const useFetchWithErrorHandling = useFeatureFlag('merge_box_use_fetch_with_error_handling')

  return useMutation({
    mutationFn: async (data: EnableAutoMergeInput) => {
      if (useFetchWithErrorHandling) {
        const response = await fetchWithErrorHandling(apiURL, {
          method: 'POST',
          headers: {
            Accept: 'application/json',
          },
          body: data,
        })
        const json = await parseJSONWithBetterErrors(response)
        const predefinedError = new MergeError(
          json?.error || 'Unknown error occurred',
          json?.metadata?.ruleErrors || [],
          response.status,
        )
        throwErrorsIfBadResponse(response, json, predefinedError)
        return json
      } else {
        const result = await reactFetchJSON(`${apiURL}`, {
          method: 'POST',
          headers: {
            Accept: 'application/json',
          },
          body: data,
        })
        const json = await result.json()
        if (result.ok) return json

        const errorMessage = json.error || 'Unknown error occurred'
        throw new MergeError(errorMessage, json.metadata?.ruleErrors || [])
      }
    },
    onSuccess: () => {
      onSuccess?.()
      return queryClient.refetchQueries({queryKey: mergeBoxQueryKey}, {cancelRefetch: false})
    },
    onError: (e: Error) => {
      onError?.(e)
    },
  })
}
