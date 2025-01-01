import {useCallback, useEffect, useState} from 'react'
import {Box, Button} from '@primer/react'
import type {MutateOptions} from '@tanstack/react-query'
import {useClickAnalytics} from '@github-ui/use-analytics'
import type {SecurityCampaignForm} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {SecurityCampaignsLimitDialog} from '../SecurityCampaignsLimitDialog'
import type {User} from '@github-ui/security-campaigns-shared/types/user'
import {
  useCreateSecurityCampaignMutation,
  type CreateSecurityCampaignRequest,
  type CreateSecurityCampaignResponse,
} from '../hooks/use-create-security-campaign-mutation'
import {SecurityCampaignsOnboardingNotice} from '../SecurityCampaignsOnboardingNotice'
import {SecurityCampaignsNoAlertsDialog} from './SecurityCampaignNoAlertsDialog'
import {NewSecurityCampaignFormDialog} from './NewSecurityCampaignFormDialog'
import {assertNever} from '../utils/assert-never'

export interface SecurityCampaignCreateButtonProps {
  // The query that should be used to filter the alerts.
  query: string

  // The number of campaigns the organization has.
  orgCampaignsCount: number

  // The maximum number of campaigns allowed for an org.
  maxCampaigns: number

  // The URL to POST to create a campaign.
  campaignCreationPath: string

  // The URL to GET to fetch possible campaign managers.
  campaignManagersPath: string

  // The URL to GET to fetch the alerts summary.
  campaignAlertsSummaryPath: string

  // The current user.
  currentUser: User

  // A flag indicating whether to show the onboarding notice or not.
  showOnboardingNotice: boolean

  // The URL to POST to dismiss the onboarding notice.
  dismissOnboardingNoticePath: string

  // Used when creating a campaign from a template.
  templateName?: string
  templateDescription?: string
  templatePresent?: boolean
  templateDialog?: string

  // Number of alerts matching the query
  alertsCount: number

  // Alerts limit per campaign
  maxAlerts: number
  maxRepos: number

  // Organization ID
  orgId: number

  // Docs URLs
  aboutCampaignsDocsUrl: string
  bestPracticeCampaignsDocsUrl: string

  // Feature flags
  showAutofixPullRequests?: boolean
}

export function SecurityCampaignCreateButton({
  query,
  orgCampaignsCount,
  maxCampaigns,
  campaignCreationPath,
  campaignManagersPath,
  campaignAlertsSummaryPath,
  currentUser,
  showOnboardingNotice,
  dismissOnboardingNoticePath,
  templateName,
  templateDescription,
  templatePresent = false,
  templateDialog,
  alertsCount,
  maxAlerts,
  maxRepos,
  orgId,
  aboutCampaignsDocsUrl,
  bestPracticeCampaignsDocsUrl,
  showAutofixPullRequests,
}: SecurityCampaignCreateButtonProps) {
  const isAlertsEmpty = alertsCount === 0

  const [isCreationDialogOpen, setIsCreationDialogOpen] = useState(templatePresent && !isAlertsEmpty)
  const [isNoAlertsDialogOpen, setIsNoAlertsDialogOpen] = useState(templatePresent && isAlertsEmpty)

  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const {mutate, isPending, error, reset} = useCreateSecurityCampaignMutation(campaignCreationPath)

  const handleSubmit = async (
    campaign: SecurityCampaignForm,
    {onSuccess, ...options}: MutateOptions<CreateSecurityCampaignResponse, Error, CreateSecurityCampaignRequest>,
  ) => {
    mutate(
      {
        campaignName: campaign.name,
        campaignDescription: campaign.description,
        campaignDueDate: campaign.endsAt,
        campaignManager: campaign.manager?.id ?? 0,
        campaignGenerateAutofixPullRequests: showAutofixPullRequests ? campaign.generateAutofixPullRequests : undefined,
        query,
      },
      {
        ...options,
        onSuccess: (response, variables, context) => {
          onSuccess?.(response, variables, context)
          window.open(response.campaignPath, '_self')
        },
      },
    )
  }

  const maxCampaignsReached = orgCampaignsCount >= maxCampaigns
  const showCampaignLimitDialog = isCreationDialogOpen && maxCampaignsReached
  const showCreationDialog = isCreationDialogOpen && !maxCampaignsReached

  const sendCreateAnalyticsEvent = useCallback(
    (shownDialog: 'creation' | 'no_alerts' | 'campaigns_limit') => {
      sendClickAnalyticsEvent({
        category: 'security_campaigns',
        action: 'create',
        label: `location:security_center_alerts_code_scanning;dialog:${shownDialog};alerts_count:${alertsCount};org_campaigns_count:${orgCampaignsCount};org_id:${orgId}`,
      })
    },
    [sendClickAnalyticsEvent, alertsCount, orgCampaignsCount, orgId],
  )

  const getShownDialog = () => {
    if (isAlertsEmpty) {
      return 'no_alerts' as const
    }
    if (maxCampaignsReached) {
      return 'campaigns_limit' as const
    }
    return 'creation' as const
  }

  const shownDialog = getShownDialog()

  const handleOnClick = () => {
    sendCreateAnalyticsEvent(shownDialog)

    switch (shownDialog) {
      case 'no_alerts':
        setIsNoAlertsDialogOpen(true)
        break
      case 'campaigns_limit':
      case 'creation':
        // The campaigns limit dialog is controlled by isCreationDialogOpen as well
        setIsCreationDialogOpen(true)
        break
      default:
        assertNever(shownDialog)
    }
  }

  useEffect(() => {
    if (templatePresent) {
      sendCreateAnalyticsEvent(shownDialog)
    }
    // Disabling exhaustive-deps as we only want to run this effect on the first render to send analytics once
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <>
      <Box sx={{display: 'flex', alignItems: 'center'}}>
        <Box sx={{position: 'relative'}}>
          <Button onClick={handleOnClick} size="medium" inactive={isAlertsEmpty}>
            Create campaign
          </Button>
          <SecurityCampaignsOnboardingNotice
            show={showOnboardingNotice}
            dismissPath={dismissOnboardingNoticePath}
            aboutCampaignsDocsUrl={aboutCampaignsDocsUrl}
          />
        </Box>
      </Box>
      {isNoAlertsDialogOpen && (
        <SecurityCampaignsNoAlertsDialog
          setIsOpen={setIsNoAlertsDialogOpen}
          templatePresent={templatePresent}
          templateDialog={templateDialog}
        />
      )}
      {showCampaignLimitDialog && (
        <SecurityCampaignsLimitDialog maxCampaigns={maxCampaigns} setIsOpen={setIsCreationDialogOpen} />
      )}
      {showCreationDialog && (
        <NewSecurityCampaignFormDialog
          setIsOpen={setIsCreationDialogOpen}
          allowDueDateInPast={false}
          submitForm={handleSubmit}
          isPending={isPending}
          formError={error}
          resetForm={reset}
          dialogTitle={templateName ? `New campaign from ${templateName} template` : 'New campaign'}
          alertsLimitReached={alertsCount > maxAlerts}
          maxAlerts={maxAlerts}
          maxRepos={maxRepos}
          templateName={templateName}
          templateDescription={templateDescription}
          currentUser={currentUser}
          query={query}
          campaignManagersPath={campaignManagersPath}
          campaignAlertsSummaryPath={campaignAlertsSummaryPath}
          bestPracticeCampaignsDocsUrl={bestPracticeCampaignsDocsUrl}
          showAutofixPullRequests={showAutofixPullRequests ?? false}
        />
      )}
    </>
  )
}
