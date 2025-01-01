import {useMutation, useQueryClient} from '@github-ui/react-query'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
  parseJSONWithBetterErrors,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'

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

  return useMutation({
    mutationFn: async (data: MutationData) => {
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
    },
    onSuccess: () => {
      return queryClient.invalidateQueries({queryKey: mergeBoxQueryKey}, {cancelRefetch: false})
    },
    onError: (e: Error) => {
      onError?.(e)
    },
  })
}
