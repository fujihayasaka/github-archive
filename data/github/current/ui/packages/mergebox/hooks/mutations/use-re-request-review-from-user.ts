import {useMutation} from '@tanstack/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'

export type MutationData = {
  reviewerLogin: string
}

type Callbacks = {
  onSuccess?: () => void
  onError?: (error: Error) => void
}

export function useReRequestReviewFromUser({onSuccess, onError}: Callbacks = {}) {
  const apiURL = usePageDataUrl(PageData.reRequestReviewFromUser)
  return useMutation({
    mutationFn: async (data: MutationData) => {
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
    },
    onSuccess: () => {
      onSuccess?.()
    },
    onError: (e: Error) => {
      onError?.(e)
    },
  })
}
