import {useMutation, useQueryClient} from '@github-ui/react-query'
import {fetchWithErrorHandling} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'

import {useMergeInstructionsPageDataQueryKey} from '../../page-data/loaders/use-merge-instructions-page-data'

export function useSetDefaultProtocol(baseRefName: string) {
  const mergeInstructionsPageDataQueryKey = useMergeInstructionsPageDataQueryKey(baseRefName)
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (apiURL: string) => {
      return fetchWithErrorHandling(apiURL, {
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
