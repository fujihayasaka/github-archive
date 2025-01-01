import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {fetchJson} from '@github-ui/security-campaigns-shared/utils/fetch-json'

export type DeleteSecurityCampaignResponse = {
  message: string
}

export function useDeleteSecurityCampaignMutation(
  path: string,
): UseMutationResult<DeleteSecurityCampaignResponse, Error, void> {
  return useMutation({
    mutationFn: () => {
      return fetchJson(path, {
        method: 'delete',
        defaultErrorMessage: 'Error deleting security campaign',
      })
    },
  })
}
