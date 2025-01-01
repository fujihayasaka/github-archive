import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import type {SecurityCampaign} from '../types/security-campaign'
import {fetchJson} from '../utils/fetch-json'

export type UpdateSecurityCampaignRequest = {
  campaignName: string
  campaignDescription: string
  campaignDueDate: string
  campaignManagers: number[]
  campaignTeamManagers: number[]
  campaignContactLink: string | null
}

export type UpdateSecurityCampaignResponse = {
  campaign: SecurityCampaign
  message?: string
  showFlashMessage?: boolean
}

export function useUpdateSecurityCampaignMutation(
  path: string,
): UseMutationResult<UpdateSecurityCampaignResponse, Error, UpdateSecurityCampaignRequest> {
  return useMutation({
    mutationFn: request => {
      return fetchJson(path, {
        method: 'put',
        body: {
          campaign_name: request.campaignName,
          campaign_description: request.campaignDescription,
          campaign_due_date: request.campaignDueDate,
          campaign_managers: request.campaignManagers,
          team_managers: request.campaignTeamManagers,
          campaign_contact_link: request.campaignContactLink,
        },
      })
    },
  })
}
