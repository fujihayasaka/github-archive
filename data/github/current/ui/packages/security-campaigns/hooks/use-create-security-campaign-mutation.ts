import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {fetchJson} from '@github-ui/security-campaigns-shared/utils/fetch-json'

export type CreateSecurityCampaignRequest = {
  campaignName: string
  campaignDescription: string
  campaignDueDate: string
  campaignManagers: number[]
  campaignTeamManagers: number[]
  campaignContactLink: string | null
  campaignGenerateAutofixPullRequests?: boolean
  campaignGenerateIssues?: boolean
  query: string
  sourceCampaignId?: number
}

export type CreateSecurityCampaignResponse = {
  message: string
  campaignNumber: number
}

export function useCreateSecurityCampaignMutation(
  path: string,
): UseMutationResult<CreateSecurityCampaignResponse, Error, CreateSecurityCampaignRequest> {
  return useMutation({
    mutationFn: request => {
      return fetchJson(path, {
        method: 'post',
        body: {
          campaign_name: request.campaignName,
          campaign_description: request.campaignDescription,
          campaign_due_date: request.campaignDueDate,
          campaign_managers: request.campaignManagers,
          team_managers: request.campaignTeamManagers,
          campaign_contact_link: request.campaignContactLink,
          campaign_generate_autofix_pull_requests: request.campaignGenerateAutofixPullRequests,
          campaign_generate_issues: request.campaignGenerateIssues,
          query: request.query,
          source_campaign_id: request.sourceCampaignId,
        },
      })
    },
  })
}
