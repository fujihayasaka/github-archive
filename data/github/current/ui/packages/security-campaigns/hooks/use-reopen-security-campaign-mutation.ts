import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import type {SecurityCampaign} from '../types/security-campaign'
import {fetchJson} from '../utils/fetch-json'

export type ReopenSecurityCampaignResponse = {
  campaign: SecurityCampaign
  showFlashMessage?: boolean
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
