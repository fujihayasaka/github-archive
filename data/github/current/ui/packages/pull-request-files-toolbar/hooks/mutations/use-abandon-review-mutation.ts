import {reactFetchJSON} from '@github-ui/verified-fetch'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {useMutation} from '@github-ui/react-query'

import type {ReviewResponse} from '../../page-data/payloads/review-response'

type Callbacks = {
  onSuccess: (json: ReviewResponse) => void
  onError: (e: Error) => void
}

export function useAbandonReviewMutation({onSuccess, onError}: Callbacks) {
  const apiURL = usePageDataUrl(PageData.abandonReview)
  return useMutation<Response>({
    mutationFn: async () => {
      return reactFetchJSON(`${apiURL}`, {
        method: 'DELETE',
        headers: {
          Accept: 'application/json',
        },
      })
    },
    onSuccess: async data => {
      const json = await data.json()
      const errorMessage = json.error || 'Unknown error occurred'
      if (!data.ok) {
        throw new Error(errorMessage)
      }

      onSuccess(json)
    },
    onError: (e: Error) => {
      onError(e)
    },
  })
}
