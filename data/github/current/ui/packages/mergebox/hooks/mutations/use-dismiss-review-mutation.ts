import {useMutation, useQueryClient} from '@github-ui/react-query'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {useMergeBoxPageDataQueryKey} from '../../page-data/loaders/use-merge-box-page-data'
import {
  fetchWithErrorHandling,
  throwErrorsIfBadResponse,
  parseJSONWithBetterErrors,
} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'

type DismissReviewInput = {
  reviewId: number
  message: string
}

export function useDismissReviewMutation() {
  const apiURL = usePageDataUrl(PageData.dismissReview)
  const mergeBoxQueryKey = useMergeBoxPageDataQueryKey()
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (data: DismissReviewInput) => {
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
  })
}
