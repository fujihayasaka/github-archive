import {reactFetchJSON} from '@github-ui/verified-fetch'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {useMutation} from '@github-ui/react-query'

import type {ReviewResponse} from '../../page-data/payloads/review-response'

export const ReviewEvent = {
  approve: 'approve',
  comment: 'comment',
  requestChanges: 'request changes',
} as const

export type ReviewEvent = (typeof ReviewEvent)[keyof typeof ReviewEvent]

type Input = {
  body: string
  event: ReviewEvent
  headSha: string
}

type Callbacks = {
  onSuccess: (json: ReviewResponse) => void
  onError: (e: Error) => void
}

export function useSubmitReviewMutation({onSuccess, onError}: Callbacks) {
  const apiURL = usePageDataUrl(PageData.submitReview)
  return useMutation<Response, Error, Input>({
    mutationFn: async ({body, event, headSha}) => {
      return reactFetchJSON(`${apiURL}`, {
        method: 'PUT',
        headers: {
          Accept: 'application/json',
        },
        body: {body, event, headSha},
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
