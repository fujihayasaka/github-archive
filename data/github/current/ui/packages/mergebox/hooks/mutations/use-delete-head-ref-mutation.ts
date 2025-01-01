import {reactFetchJSON} from '@github-ui/verified-fetch'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import {useMutation} from '@tanstack/react-query'
import {useMergeBoxPageDataQueryKey} from '../../page-data/loaders/use-merge-box-page-data'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'

export function useDeleteHeadRefMutation({onError}: {onError: (error: Error) => void}) {
  const apiURL = usePageDataUrl(PageData.deleteHeadRef)
  const mergeBoxQueryKey = useMergeBoxPageDataQueryKey()

  return useMutation({
    mutationFn: async () => {
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
    },
    onSuccess: () => {
      return queryClient.invalidateQueries({queryKey: mergeBoxQueryKey}, {cancelRefetch: false})
    },
    onError: (e: Error) => {
      onError(e)
    },
  })
}
