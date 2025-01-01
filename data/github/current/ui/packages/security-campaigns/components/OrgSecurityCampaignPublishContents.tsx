import {securityCampaignOrgCampaignAlertsSummaryPath, securityCampaignOrgCampaignsPath} from '@github-ui/paths'
import {SecurityCampaignFormWrapper} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormWrapper'
import type {User} from '@github-ui/security-campaigns-shared/types/user'
import {Breadcrumbs, PageHeader} from '@primer/react'
import {SecurityCampaignOpenFormContents} from './SecurityCampaignOpenFormContents'
import type {SecurityCampaignForm} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {useAlertsSummaryQuery} from '@github-ui/security-campaigns-shared/hooks/use-alerts-summary-query'
import {SecurityCampaignPublishButtons} from './SecurityCampaignPublishButtons'
import {Banner} from '@primer/react/experimental'
import type {CampaignInitialValues} from '@github-ui/security-campaigns-shared/types/campaign-initial-values'

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

      <Breadcrumbs>
        <Breadcrumbs.Item href={securityCampaignOrgCampaignsPath({org: organizationLogin})}>Campaigns</Breadcrumbs.Item>
        <Breadcrumbs.Item href={breadcrumbHref}>{breadcrumbText}</Breadcrumbs.Item>
        <Breadcrumbs.Item selected>Publish</Breadcrumbs.Item>
      </Breadcrumbs>
      <PageHeader aria-label="Publish campaign">
        <PageHeader.TitleArea>
          <PageHeader.Title>Publish campaign</PageHeader.Title>
        </PageHeader.TitleArea>
      </PageHeader>
      <hr />
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
