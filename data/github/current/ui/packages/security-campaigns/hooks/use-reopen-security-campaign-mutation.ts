import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {fetchJson} from '@github-ui/security-campaigns-shared/utils/fetch-json'

export function useReopenSecurityCampaignMutation(path: string): UseMutationResult<void, Error, void> {
  return useMutation({
    mutationFn: () => {
      return fetchJson(path, {
        method: 'post',
        defaultErrorMessage: 'Error reopening security campaign',
      })
    },
  })
}
