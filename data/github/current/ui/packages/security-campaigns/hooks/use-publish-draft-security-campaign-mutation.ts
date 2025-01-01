import {securityCampaignOrgPublishDraftPath} from '@github-ui/paths'
import {useMutation, type UseMutationResult} from '@github-ui/react-query'
import {fetchJson} from '../utils/fetch-json'

export type PublishDraftSecurityCampaignRequest = {
  campaignName: string
  campaignDescription: string
  campaignDueDate: string
  campaignManagers: number[]
  campaignTeamManagers: number[]
  campaignContactLink: string | null
  campaignGenerateAutofixPullRequests?: boolean
  campaignGenerateIssues?: boolean
  query: string
}

export type PublishDraftSecurityCampaignResponse = {
  campaignNumber: number
  message?: string | null
}

export function usePublishDraftSecurityCampaignMutation(
  organizationLogin: string,
  securityCampaignNumber: number,
): UseMutationResult<PublishDraftSecurityCampaignResponse, Error, PublishDraftSecurityCampaignRequest> {
  return useMutation({
    mutationFn: request => {
      return fetchJson(securityCampaignOrgPublishDraftPath({org: organizationLogin, securityCampaignNumber}), {
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
        },
      })
    },
  })
}
