import {securityCampaignOrgCampaignCreateDraftPath} from '@github-ui/paths'
import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {fetchJson} from '@github-ui/security-campaigns-shared/utils/fetch-json'

export type CreateDraftSecurityCampaignRequest = {
  campaignName: string
  campaignDescription?: string | null
  campaignDueDate?: string | null
  campaignManagers: number[]
  campaignTeamManagers: number[]
  campaignContactLink?: string | null
  query: string
}

export type CreateDraftSecurityCampaignResponse = {
  message: string
  campaignNumber: number
}

export function useCreateDraftSecurityCampaignMutation(
  organizationLogin: string,
): UseMutationResult<CreateDraftSecurityCampaignResponse, Error, CreateDraftSecurityCampaignRequest> {
  return useMutation({
    mutationFn: request => {
      return fetchJson(securityCampaignOrgCampaignCreateDraftPath({org: organizationLogin}), {
        method: 'post',
        body: {
          campaign_name: request.campaignName,
          campaign_description: request.campaignDescription,
          campaign_due_date: request.campaignDueDate,
          campaign_managers: request.campaignManagers,
          team_managers: request.campaignTeamManagers,
          campaign_contact_link: request.campaignContactLink,
          query: request.query,
        },
      })
    },
  })
}
