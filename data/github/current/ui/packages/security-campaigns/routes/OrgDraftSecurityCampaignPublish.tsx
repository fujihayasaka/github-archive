import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {securityCampaignOrgCampaignPath} from '@github-ui/paths'
import type {DraftSecurityCampaign, SecurityCampaignForm} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import type {User} from '@github-ui/security-campaigns-shared/types/user'
import {usePublishDraftSecurityCampaignMutation} from '../hooks/use-publish-draft-security-campaign-mutation'
import {useNavigate} from '@github-ui/use-navigate'
import {useCallback} from 'react'
import {OrgSecurityCampaignPublishContents} from '../components/OrgSecurityCampaignPublishContents'

export type OrgDraftSecurityCampaignPublishPayload = {
  campaign: DraftSecurityCampaign
  organizationLogin: string
  currentUser: User
  maxManagers: number
  orgOpenCampaignsCount: number
  maxOpenCampaigns: number

  // Feature flags
  showAutofixPullRequests: boolean
  showGenerateIssues: boolean
}

export const OrgDraftSecurityCampaignPublish = () => {
  const {
    organizationLogin,
    campaign,
    currentUser,
    maxManagers,
    orgOpenCampaignsCount,
    maxOpenCampaigns,
    showAutofixPullRequests,
    showGenerateIssues,
  } = useRoutePayload<OrgDraftSecurityCampaignPublishPayload>()

  const navigate = useNavigate()

  const {mutate, isPending, isSuccess, error, reset} = usePublishDraftSecurityCampaignMutation(
    organizationLogin,
    campaign.number,
  )

  const publishCampaign = useCallback(
    (campaignForm: SecurityCampaignForm) => {
      mutate(
        {
          campaignName: campaignForm.name,
          campaignDescription: campaignForm.description,
          campaignDueDate: campaignForm.endsAt,
          campaignManagers: campaignForm.managers.map(manager => manager.id),
          campaignTeamManagers: campaignForm.teamManagers.map(team => team.id),
          campaignContactLink: campaignForm.contactLink,
          campaignGenerateAutofixPullRequests: showAutofixPullRequests
            ? campaignForm.generateAutofixPullRequests
            : undefined,
          campaignGenerateIssues: showGenerateIssues ? campaignForm.generateIssues : undefined,
          query: campaign.creationQuery,
        },
        {
          onSuccess: response => {
            navigate(
              securityCampaignOrgCampaignPath({
                org: organizationLogin,
                securityCampaignNumber: response.campaignNumber,
              }),
            )
          },
        },
      )
    },
    [mutate, navigate, organizationLogin, campaign.creationQuery, showAutofixPullRequests, showGenerateIssues],
  )

  return (
    <OrgSecurityCampaignPublishContents
      organizationLogin={organizationLogin}
      breadcrumbHref={securityCampaignOrgCampaignPath({
        org: organizationLogin,
        securityCampaignNumber: campaign.number,
      })}
      breadcrumbText={campaign.name}
      currentUser={currentUser}
      maxManagers={maxManagers}
      publishCampaign={publishCampaign}
      reset={reset}
      isPending={isPending || isSuccess}
      error={error}
      showAutofixPullRequests={showAutofixPullRequests}
      showGenerateIssues={showGenerateIssues}
      creationQuery={campaign.creationQuery}
      cancelHref={securityCampaignOrgCampaignPath({
        org: organizationLogin,
        securityCampaignNumber: campaign.number,
      })}
      maxOpenCampaignsReached={orgOpenCampaignsCount === maxOpenCampaigns}
      maxOpenCampaigns={maxOpenCampaigns}
      initialValues={campaign}
    />
  )
}
