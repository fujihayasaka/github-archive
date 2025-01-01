import {reactFetchJSON} from '@github-ui/verified-fetch'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {fetchWithErrorHandling} from '@github-ui/pull-request-page-data-tooling/fetch-error-handling'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

import {useMergeInstructionsPageDataQueryKey} from '../../page-data/loaders/use-merge-instructions-page-data'

export function useSetDefaultProtocol(baseRefName: string) {
  const mergeInstructionsPageDataQueryKey = useMergeInstructionsPageDataQueryKey(baseRefName)
  const queryClient = useQueryClient()
  const useFetchWithErrorHandling = useFeatureFlag('merge_box_use_fetch_with_error_handling')

  return useMutation({
    mutationFn: async (apiURL: string) => {
      if (useFetchWithErrorHandling) {
        return fetchWithErrorHandling(apiURL, {
          method: 'POST',
          headers: {
            Accept: 'application/json',
          },
        })
      } else {
        return reactFetchJSON(apiURL, {
          method: 'POST',
          headers: {
            Accept: 'application/json',
          },
        })
      }
    },
    onSuccess: () => {
      return queryClient.invalidateQueries({queryKey: mergeInstructionsPageDataQueryKey}, {cancelRefetch: false})
    },
  })
}
