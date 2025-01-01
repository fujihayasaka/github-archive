import {useMutation} from '@tanstack/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {usePageDataUrl} from '@github-ui/pull-request-page-data-tooling/use-page-data-url'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {useMergeBoxPageDataQueryKey} from '../../page-data/loaders/use-merge-box-page-data'
import {MergeError} from '../../helpers/merge-error'

type EnableAutoMergeInput = {
  authorEmail?: string
  commitMessage?: string | null | undefined
  commitTitle?: string | null | undefined
  mergeMethod?: string
}

type Callbacks = {
  onError?: (error: Error) => void
}
export function useEnableAutoMergeMutation({onError}: Callbacks = {}) {
  const apiURL = usePageDataUrl(PageData.enableAutoMerge)
  const mergeBoxQueryKey = useMergeBoxPageDataQueryKey()
  return useMutation({
    mutationFn: async (data: EnableAutoMergeInput) => {
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
    },
    onSuccess: () => {
      return queryClient.refetchQueries({queryKey: mergeBoxQueryKey}, {cancelRefetch: false})
    },
    onError: (e: Error) => {
      onError?.(e)
    },
  })
}
