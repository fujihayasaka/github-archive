import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {fetchJson} from '../utils/fetch-json'

export type DeleteSecurityCampaignResponse = {
  showFlashMessage?: boolean
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
