import {useMutation, useQueryClient} from '@github-ui/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
  parseJSONWithBetterErrors,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

import {useMergeBoxPageDataQueryKey} from '../../page-data/loaders/use-merge-box-page-data'

export type MutationData = {
  reviewerLogin: string
}

type Callbacks = {
  onError?: (error: Error) => void
}

export function useReRequestReviewFromUser({onError}: Callbacks = {}) {
  const mergeBoxQueryKey = useMergeBoxPageDataQueryKey()
  const apiURL = usePageDataUrl(PageData.reRequestReviewFromUser)
  const queryClient = useQueryClient()
  const useFetchWithErrorHandling = useFeatureFlag('merge_box_use_fetch_with_error_handling')

  return useMutation({
    mutationFn: async (data: MutationData) => {
      if (useFetchWithErrorHandling) {
        const response = await fetchWithErrorHandling(apiURL, {
          method: 'POST',
          headers: {
            Accept: 'application/json',
          },
          body: data,
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
          body: data,
        })
        const json = await result.json()
        if (result.ok) return json

        const errorMessage = json.error || 'Unknown error occurred'
        throw new Error(errorMessage)
      }
    },
    onSuccess: () => {
      return queryClient.invalidateQueries({queryKey: mergeBoxQueryKey}, {cancelRefetch: false})
    },
    onError: (e: Error) => {
      onError?.(e)
    },
  })
}
