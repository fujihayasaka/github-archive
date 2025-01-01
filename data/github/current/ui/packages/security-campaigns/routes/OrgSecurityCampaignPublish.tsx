import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {OrgSecurityCampaignPublishContents} from '../components/OrgSecurityCampaignPublishContents'
import {useBannerContext} from '@github-ui/role-assignments/banner-provider'
import {useCreateSecurityCampaignMutation} from '../hooks/use-create-security-campaign-mutation'
import {
  securityCampaignOrgCampaignCreatePath,
  securityCampaignOrgCampaignPath,
  securityCampaignsOrgNewCampaignPath,
} from '@github-ui/paths'
import {useCallback} from 'react'
import type {CampaignInitialValues} from '../types/campaign-initial-values'
import type {SecurityCampaignForm} from '../types/security-campaign'
import type {User} from '../types/user'

export type OrgSecurityCampaignPublishPayload = {
  organizationLogin: string
  currentUser: User
  maxManagers: number
  creationQuery: string
  orgOpenCampaignsCount: number
  maxOpenCampaigns: number
  campaignName: string | null
  campaignDescription: string | null

  // Feature flags
  showAutofixPullRequests: boolean
  showGenerateIssues: boolean
}

export const OrgSecurityCampaignPublish = () => {
  const {
    organizationLogin,
    currentUser,
    maxManagers,
    creationQuery,
    orgOpenCampaignsCount,
    maxOpenCampaigns,
    showAutofixPullRequests,
    campaignName,
    campaignDescription,
    showGenerateIssues,
  } = useRoutePayload<OrgSecurityCampaignPublishPayload>()

  const {navigate} = useBannerContext()

  const {mutate, isPending, isSuccess, error, reset} = useCreateSecurityCampaignMutation(
    securityCampaignOrgCampaignCreatePath({org: organizationLogin}),
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
          query: creationQuery,
        },
        {
          onSuccess: response => {
            navigate(
              securityCampaignOrgCampaignPath({
                org: organizationLogin,
                securityCampaignNumber: response.campaignNumber,
              }),
              {},
              {
                message: response.message,
                variant: 'success',
              },
            )
          },
        },
      )
    },
    [mutate, navigate, showAutofixPullRequests, showGenerateIssues, creationQuery, organizationLogin],
  )

  const initialValues: CampaignInitialValues = {
    name: campaignName,
    description: campaignDescription,
    endsAt: null,
    managers: [],
    teamManagers: [],
    contactLink: null,
  }

  return (
    <OrgSecurityCampaignPublishContents
      initialValues={initialValues}
      organizationLogin={organizationLogin}
      breadcrumbHref={securityCampaignsOrgNewCampaignPath({
        org: organizationLogin,
        query: creationQuery,
      })}
      breadcrumbText="Select filters"
      currentUser={currentUser}
      maxManagers={maxManagers}
      publishCampaign={publishCampaign}
      reset={reset}
      isPending={isPending || isSuccess}
      error={error}
      showAutofixPullRequests={showAutofixPullRequests}
      showGenerateIssues={showGenerateIssues}
      cancelHref={securityCampaignsOrgNewCampaignPath({org: organizationLogin, query: creationQuery})}
      creationQuery={creationQuery}
      maxOpenCampaignsReached={orgOpenCampaignsCount === maxOpenCampaigns}
      maxOpenCampaigns={maxOpenCampaigns}
    />
  )
}
