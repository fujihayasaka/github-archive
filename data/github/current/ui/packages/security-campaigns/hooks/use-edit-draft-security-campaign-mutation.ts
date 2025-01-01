import {securityCampaignOrgCampaignEditDraftPath} from '@github-ui/paths'
import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {fetchJson} from '@github-ui/security-campaigns-shared/utils/fetch-json'

export type EditDraftSecurityCampaignRequest = {
  campaignName: string
  campaignDescription?: string | null
  campaignDueDate?: string | null
  campaignManagers: number[]
  campaignTeamManagers: number[]
  campaignContactLink?: string | null
  query: string
}

export type EditDraftSecurityCampaignResponse = {
  message: string
  campaignNumber: number
}

export function useEditDraftSecurityCampaignMutation(
  organizationLogin: string,
  campaignNumber: number,
): UseMutationResult<void, Error, EditDraftSecurityCampaignRequest> {
  return useMutation({
    mutationFn: request => {
      return fetchJson(
        securityCampaignOrgCampaignEditDraftPath({org: organizationLogin, securityCampaignNumber: campaignNumber}),
        {
          method: 'put',
          body: {
            campaign_name: request.campaignName,
            campaign_description: request.campaignDescription,
            campaign_due_date: request.campaignDueDate,
            campaign_managers: request.campaignManagers,
            team_managers: request.campaignTeamManagers,
            campaign_contact_link: request.campaignContactLink,
            query: request.query,
          },
        },
      )
    },
  })
}
