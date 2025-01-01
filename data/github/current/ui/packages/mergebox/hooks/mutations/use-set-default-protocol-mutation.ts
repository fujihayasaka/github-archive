import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {useMutation} from '@tanstack/react-query'
import {useMergeInstructionsPageDataQueryKey} from '../../page-data/loaders/use-merge-instructions-page-data'

export function useSetDefaultProtocol(baseRefName: string) {
  const mergeInstructionsPageDataQueryKey = useMergeInstructionsPageDataQueryKey(baseRefName)
  return useMutation({
    mutationFn: async (apiURL: string) => {
      return reactFetchJSON(apiURL, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
        },
      })
    },
    onSuccess: () => {
      return queryClient.invalidateQueries({queryKey: mergeInstructionsPageDataQueryKey}, {cancelRefetch: false})
    },
  })
}
