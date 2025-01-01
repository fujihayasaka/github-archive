import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {fetchJson} from '../utils/fetch-json'
import type {SecurityCampaign} from '../types/security-campaign'

export type CloseSecurityCampaignResponse = {
  campaign: SecurityCampaign
  indexPageEnabled?: boolean
  showFlashMessage?: boolean
}

export function useCloseSecurityCampaignMutation(
  path: string,
): UseMutationResult<CloseSecurityCampaignResponse, Error, void> {
  return useMutation({
    mutationFn: () => {
      return fetchJson(path, {
        method: 'post',
        defaultErrorMessage: 'Error closing security campaign',
      })
    },
  })
}
