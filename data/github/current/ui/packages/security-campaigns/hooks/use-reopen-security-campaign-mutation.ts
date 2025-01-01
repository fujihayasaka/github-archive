import {useMutation, type UseMutationResult} from '@tanstack/react-query'
import {fetchJson} from '@github-ui/security-campaigns-shared/utils/fetch-json'

export type ReopenSecurityCampaignResponse = {
  redirect: string
}

export function useReopenSecurityCampaignMutation(
  path: string,
): UseMutationResult<ReopenSecurityCampaignResponse, Error, void> {
  return useMutation({
    mutationFn: () => {
      return fetchJson(path, {
        method: 'post',
        defaultErrorMessage: 'Error reopening security campaign',
      })
    },
  })
}
