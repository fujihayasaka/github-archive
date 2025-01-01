import {Heading, Stack} from '@primer/react'
import {CampaignsCountsMetric} from '../components/CampaignsCountsMetric'
import {AutofixStatsMetric} from '../components/AutofixStatsMetric'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {SecurityCampaignsList} from '../components/SecurityCampaignsList'
import type {SecurityCampaignTemplate} from '../types/security-campaign-template'
import {useState} from 'react'
import {NoCampaignsBlankSlate} from '../components/NoCampaignsBlankSlate'
import {TemplateSelectionDialog} from '../components/TemplateSelectionDialog'
import {CampaignCreationButton} from '../components/CampaignCreationButton'
import {useCampaignsCountsQuery} from '../hooks/use-campaigns-counts-query'
import type {SecurityCampaignCounts} from '../types/security-campaign-counts'
import {CampaignFeedbackLink} from '../components/CampaignFeedbackLink'

export interface OrgSecurityCampaignsIndexPayload {
  campaignCounts: SecurityCampaignCounts
  autofixMetricsEnabled: boolean
  organizationLogin: string
  showFullView: boolean
  templates: SecurityCampaignTemplate[]
  aboutCampaignsDocsUrl: string
  maxOpenCampaigns: number
  maxDraftCampaigns: number
}

export const OrgSecurityCampaignsIndex = () => {
  const {
    campaignCounts: initialCampaignCounts,
    autofixMetricsEnabled,
    showFullView,
    organizationLogin,
    templates,
    aboutCampaignsDocsUrl,
    maxOpenCampaigns,
    maxDraftCampaigns,
  } = useRoutePayload<OrgSecurityCampaignsIndexPayload>()

  const {data: campaignCounts} = useCampaignsCountsQuery(organizationLogin, initialCampaignCounts)

  const {
    openCampaignsCount,
    openCampaignsTotalCount,
    openCampaignsOpenCount,
    openCampaignsInProgressCount,
    openCampaignsFixedCount,
    openCampaignsDismissedCount,
    closedCampaignsCount,
    closedCampaignsTotalCount,
    closedCampaignsOpenCount,
    closedCampaignsFixedCount,
    closedCampaignsDismissedCount,
    draftCampaignsCount,
    autofixGeneratedCount,
    autofixAppliedCount,
    openCampaignsCountWithSpam,
    draftCampaignsCountWithSpam,
    hasOpenSpam,
    hasDraftSpam,
  } = campaignCounts ?? initialCampaignCounts

  const anyCampaigns = openCampaignsCount + closedCampaignsCount + draftCampaignsCount > 0

  const [isTemplatesDialogOpen, setIsTemplatesDialogOpen] = useState(false)

  const showCampaignCreationButton = showFullView && anyCampaigns
  const maxCampaignsReached =
    draftCampaignsCountWithSpam === maxDraftCampaigns && openCampaignsCountWithSpam === maxOpenCampaigns

  return (
    <>
      {isTemplatesDialogOpen && (
        <TemplateSelectionDialog
          setIsOpen={setIsTemplatesDialogOpen}
          templates={templates}
          organizationLogin={organizationLogin}
        />
      )}
      <Stack direction="horizontal" justify="space-between" align="center" gap="normal">
        <Heading as="h2" className="f2 text-normal">
          Campaigns
        </Heading>
        <Stack direction="horizontal" align="center" gap="condensed">
          <CampaignFeedbackLink />
          {showCampaignCreationButton && (
            <CampaignCreationButton
              organizationLogin={organizationLogin}
              maxCampaignsReached={maxCampaignsReached}
              hasSpam={hasOpenSpam || hasDraftSpam}
              maxOpenCampaigns={maxOpenCampaigns}
              maxDraftCampaigns={maxDraftCampaigns}
              setIsTemplatesDialogOpen={setIsTemplatesDialogOpen}
            />
          )}
        </Stack>
      </Stack>
      <p className="fgColor-muted">Accelerate the remediation of security alerts with the help of Copilot Autofix.</p>
      {anyCampaigns ? (
        <>
          {showFullView && (
            <div className="d-flex flex-auto flex-column flex-md-row gap-2 pt-1">
              <CampaignsCountsMetric
                title="Open campaigns"
                description="Total alerts included in open campaigns."
                campaignsCount={openCampaignsCount}
                totalAlertCount={openCampaignsTotalCount}
                // We display open alerts next to in progress alerts, so we prefer to show the disjoint counts here
                openAlertsCount={openCampaignsOpenCount - openCampaignsInProgressCount}
                inProgressAlertsCount={openCampaignsInProgressCount}
                fixedAlertsCount={openCampaignsFixedCount}
                dismissedAlertsCount={openCampaignsDismissedCount}
              />
              <CampaignsCountsMetric
                title="Closed campaigns"
                description="Total alerts included in closed campaigns."
                campaignsCount={closedCampaignsCount}
                totalAlertCount={closedCampaignsTotalCount}
                openAlertsCount={closedCampaignsOpenCount}
                fixedAlertsCount={closedCampaignsFixedCount}
                dismissedAlertsCount={closedCampaignsDismissedCount}
              />
              {autofixMetricsEnabled && (
                <AutofixStatsMetric generatedCount={autofixGeneratedCount} appliedCount={autofixAppliedCount} />
              )}
            </div>
          )}
          <div className="mt-3">
            <SecurityCampaignsList
              showFullView={showFullView}
              organizationLogin={organizationLogin}
              openCount={openCampaignsCount}
              closedCount={closedCampaignsCount}
              draftCount={draftCampaignsCount}
              maxOpenCampaigns={maxOpenCampaigns}
              hasOpenSpam={hasOpenSpam}
              openCountWithSpam={openCampaignsCountWithSpam}
            />
          </div>
        </>
      ) : (
        <NoCampaignsBlankSlate
          organizationLogin={organizationLogin}
          creationAllowed={showFullView}
          maxCampaignsReached={maxCampaignsReached}
          maxOpenCampaigns={maxOpenCampaigns}
          maxDraftCampaigns={maxDraftCampaigns}
          setIsTemplatesDialogOpen={setIsTemplatesDialogOpen}
          aboutCampaignsDocsUrl={aboutCampaignsDocsUrl}
          hasSpam={hasOpenSpam || hasDraftSpam}
        />
      )}
    </>
  )
}
