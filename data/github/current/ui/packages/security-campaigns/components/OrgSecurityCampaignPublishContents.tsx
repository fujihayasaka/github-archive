import {securityCampaignOrgCampaignAlertsSummaryPath, securityCampaignOrgCampaignsPath} from '@github-ui/paths'
import {Breadcrumbs, PageHeader} from '@primer/react'
import {SecurityCampaignOpenFormContents} from './SecurityCampaignOpenFormContents'
import {SecurityCampaignPublishButtons} from './SecurityCampaignPublishButtons'
import {Banner} from '@primer/react/experimental'
import type {User} from '../types/user'
import {useAlertsSummaryQuery} from '../hooks/use-alerts-summary-query'
import type {CampaignInitialValues} from '../types/campaign-initial-values'
import type {SecurityCampaignForm} from '../types/security-campaign'
import {SecurityCampaignFormWrapper} from './SecurityCampaignFormWrapper'

interface OrgSecurityCampaignPublishContentsProps {
  organizationLogin: string
  breadcrumbHref: string
  breadcrumbText: string
  currentUser: User
  maxManagers: number
  publishCampaign: (campaignForm: SecurityCampaignForm) => void
  reset: () => void
  isPending: boolean
  error: Error | null
  showAutofixPullRequests: boolean
  showGenerateIssues: boolean
  creationQuery: string
  cancelHref: string
  maxOpenCampaignsReached: boolean
  maxOpenCampaigns: number
  initialValues?: CampaignInitialValues
}

export function OrgSecurityCampaignPublishContents({
  organizationLogin,
  breadcrumbHref,
  breadcrumbText,
  currentUser,
  maxManagers,
  publishCampaign,
  reset,
  isPending,
  error,
  showAutofixPullRequests,
  showGenerateIssues,
  creationQuery,
  cancelHref,
  maxOpenCampaignsReached,
  maxOpenCampaigns,
  initialValues,
}: OrgSecurityCampaignPublishContentsProps) {
  const {data: alertsSummary} = useAlertsSummaryQuery(
    securityCampaignOrgCampaignAlertsSummaryPath({org: organizationLogin}),
    {
      query: creationQuery,
    },
    {
      enabled: showGenerateIssues || showAutofixPullRequests,
    },
  )

  return (
    <>
      {maxOpenCampaignsReached && (
        <Banner
          variant="critical"
          hideTitle
          title={`This organization has reached the limit of ${maxOpenCampaigns} active campaigns.`}
          description={`This organization has reached the limit of ${maxOpenCampaigns} active campaigns. To create a new campaign,
          first delete or close an existing one.`}
          className="mb-2"
          data-testid="warning-banner"
        />
      )}

      <Breadcrumbs className="mb-2">
        <Breadcrumbs.Item href={securityCampaignOrgCampaignsPath({org: organizationLogin})}>Campaigns</Breadcrumbs.Item>
        <Breadcrumbs.Item href={breadcrumbHref}>{breadcrumbText}</Breadcrumbs.Item>
        <Breadcrumbs.Item selected>Publish</Breadcrumbs.Item>
      </Breadcrumbs>
      <PageHeader aria-label="Publish campaign" className="f2 text-normal">
        <PageHeader.TitleArea>
          <PageHeader.Title>Publish campaign</PageHeader.Title>
        </PageHeader.TitleArea>
      </PageHeader>
      <hr className="mt-2 mb-3" />
      <SecurityCampaignFormWrapper
        initialValues={initialValues}
        currentUser={currentUser}
        maxManagers={maxManagers}
        allowDueDateInPast={false}
        submitForm={publishCampaign}
        reset={reset}
        isPending={isPending}
        formError={error}
      >
        <SecurityCampaignOpenFormContents
          organizationLogin={organizationLogin}
          maxManagers={maxManagers}
          showAutofixPullRequests={showAutofixPullRequests}
          showGenerateIssues={showGenerateIssues}
          repositoriesWithIssuesCount={alertsSummary?.repositories?.filter(repo => repo.issuesEnabled)?.length}
          repositoriesWithPullRequestsCount={alertsSummary?.repositories?.length}
        />

        <SecurityCampaignPublishButtons cancelHref={cancelHref} maxOpenCampaignsReached={maxOpenCampaignsReached} />
      </SecurityCampaignFormWrapper>
    </>
  )
}
