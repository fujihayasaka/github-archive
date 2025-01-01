import {Box, Heading} from '@primer/react'
import {CampaignsCountsMetric} from '../components/CampaignsCountsMetric'
import {AutofixStatsMetric} from '../components/AutofixStatsMetric'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {SecurityCampaignsList} from '../components/SecurityCampaignsList'
import type {SecurityCampaignTemplate} from '../types/security-campaign-template'
import {useState} from 'react'
import {NoCampaignsBlankSlate} from '../components/NoCampaignsBlankSlate'
import {TemplateSelectionDialog} from '../components/TemplateSelectionDialog'
import {CampaignCreationButton} from '../components/CampaignCreationButton'

export interface OrgSecurityCampaignsIndexPayload {
  autofixMetricsEnabled: boolean
  openCampaignsCount: number
  openCampaignsTotalCount: number
  openCampaignsOpenCount: number
  openCampaignsInProgressCount: number
  openCampaignsFixedCount: number
  openCampaignsDismissedCount: number
  closedCampaignsCount: number
  closedCampaignsTotalCount: number
  closedCampaignsOpenCount: number
  closedCampaignsFixedCount: number
  closedCampaignsDismissedCount: number
  draftCampaignsCount: number
  autofixGeneratedCount: number
  autofixAppliedCount: number
  organizationLogin: string
  showFullView: boolean
  templates: SecurityCampaignTemplate[]
  aboutCampaignsDocsUrl: string
  draftCampaignsEnabled: boolean
  maxOpenCampaigns: number
  maxDraftCampaigns: number
}

export const OrgSecurityCampaignsIndex = () => {
  const {
    autofixMetricsEnabled,
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
    showFullView,
    organizationLogin,
    templates,
    aboutCampaignsDocsUrl,
    draftCampaignsEnabled,
    maxOpenCampaigns,
    maxDraftCampaigns,
  } = useRoutePayload<OrgSecurityCampaignsIndexPayload>()

  const anyCampaigns = openCampaignsCount + closedCampaignsCount + draftCampaignsCount > 0

  const [isTemplatesDialogOpen, setIsTemplatesDialogOpen] = useState(false)

  const showCampaignCreationButton = showFullView && anyCampaigns
  const maxCampaignsReached = draftCampaignsCount === maxDraftCampaigns && openCampaignsCount === maxOpenCampaigns

  return (
    <>
      {isTemplatesDialogOpen && (
        <TemplateSelectionDialog
          setIsOpen={setIsTemplatesDialogOpen}
          templates={templates}
          organizationLogin={organizationLogin}
        />
      )}
      <Box sx={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 3}}>
        <Heading as="h2" className="f2 text-normal">
          Campaigns
        </Heading>
        {showCampaignCreationButton && (
          <>
            <CampaignCreationButton
              organizationLogin={organizationLogin}
              maxCampaignsReached={maxCampaignsReached}
              maxOpenCampaigns={maxOpenCampaigns}
              maxDraftCampaigns={maxDraftCampaigns}
              setIsTemplatesDialogOpen={setIsTemplatesDialogOpen}
              draftCampaignsEnabled={draftCampaignsEnabled}
            />
          </>
        )}
      </Box>
      <p className="fgColor-muted mb-2">
        Accelerate the remediation of security alerts with the help of Copilot Autofix.
      </p>
      {anyCampaigns ? (
        <>
          {showFullView && (
            <Box sx={{display: 'flex', gap: 2, pt: 3}}>
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
            </Box>
          )}
          <div className="mt-2">
            <SecurityCampaignsList
              showFullView={showFullView}
              organizationLogin={organizationLogin}
              openCount={openCampaignsCount}
              closedCount={closedCampaignsCount}
              draftCount={draftCampaignsCount}
              maxOpenCampaigns={maxOpenCampaigns}
              draftCampaignsEnabled={draftCampaignsEnabled}
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
          draftCampaignsEnabled={draftCampaignsEnabled}
          aboutCampaignsDocsUrl={aboutCampaignsDocsUrl}
        />
      )}
    </>
  )
}
