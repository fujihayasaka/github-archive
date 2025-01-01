import {useCallback, useEffect, useState} from 'react'
import {Box, Button} from '@primer/react'
import type {MutateOptions} from '@github-ui/react-query'
import {useNavigate} from '@github-ui/use-navigate'
import {useClickAnalytics} from '@github-ui/use-analytics'
import type {SecurityCampaign, SecurityCampaignForm} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {SecurityCampaignsLimitDialog} from './SecurityCampaignsLimitDialog'
import type {User} from '@github-ui/security-campaigns-shared/types/user'
import {
  useCreateSecurityCampaignMutation,
  type CreateSecurityCampaignRequest,
  type CreateSecurityCampaignResponse,
} from './hooks/use-create-security-campaign-mutation'
import {SecurityCampaignsOnboardingNotice} from './SecurityCampaignsOnboardingNotice'
import {SecurityCampaignsNoAlertsDialog} from './components/SecurityCampaignNoAlertsDialog'
import {NewSecurityCampaignFormDialog} from './components/NewSecurityCampaignFormDialog'
import {assertNever} from '@github-ui/security-campaigns-shared/utils/assert-never'
import {securityCampaignOrgCampaignCreatePath, securityCampaignOrgCampaignPath} from '@github-ui/paths'

export interface SecurityCampaignCreationProps {
  // The login of the organization that this campaign is being created for.
  organizationLogin: string

  // The query that should be used to filter the alerts.
  query: string

  // The number of campaigns the organization has.
  orgCampaignsCount: number

  // The maximum number of campaigns allowed for an org.
  maxCampaigns: number

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
  maxManagers: number

  // Organization ID
  orgId: number

  // Docs URLs
  aboutCampaignsDocsUrl: string
  bestPracticeCampaignsDocsUrl: string

  // Feature flags
  showAutofixPullRequests?: boolean
  showGenerateIssues?: boolean
  campaignsGAEnabled?: boolean
  sourceCampaign: SecurityCampaign | null
}

export function SecurityCampaignCreation({
  organizationLogin,
  query,
  orgCampaignsCount,
  maxCampaigns,
  currentUser,
  showOnboardingNotice,
  dismissOnboardingNoticePath,
  templateName,
  templateDescription,
  templatePresent = false,
  templateDialog,
  alertsCount,
  maxAlerts,
  maxManagers,
  orgId,
  aboutCampaignsDocsUrl,
  bestPracticeCampaignsDocsUrl,
  showAutofixPullRequests,
  showGenerateIssues,
  campaignsGAEnabled,
  sourceCampaign,
}: SecurityCampaignCreationProps) {
  const isAlertsEmpty = alertsCount === 0

  const [isCreationDialogOpen, setIsCreationDialogOpen] = useState(
    (templatePresent || sourceCampaign) && !isAlertsEmpty,
  )
  const [isNoAlertsDialogOpen, setIsNoAlertsDialogOpen] = useState((templatePresent || sourceCampaign) && isAlertsEmpty)

  const navigate = useNavigate()
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const {mutate, isPending, error, reset} = useCreateSecurityCampaignMutation(
    securityCampaignOrgCampaignCreatePath({org: organizationLogin}),
  )

  const handleSubmit = async (
    campaign: SecurityCampaignForm,
    {onSuccess, ...options}: MutateOptions<CreateSecurityCampaignResponse, Error, CreateSecurityCampaignRequest>,
  ) => {
    mutate(
      {
        campaignName: campaign.name,
        campaignDescription: campaign.description,
        campaignDueDate: campaign.endsAt,
        campaignManagers: campaign.managers.map(manager => manager.id),
        campaignTeamManagers: campaign.teamManagers.map(team => team.id),
        campaignContactLink: campaign.contactLink,
        campaignGenerateAutofixPullRequests: showAutofixPullRequests ? campaign.generateAutofixPullRequests : undefined,
        campaignGenerateIssues: showGenerateIssues ? campaign.generateIssues : undefined,
        query,
        sourceCampaignId: sourceCampaign?.id,
      },
      {
        ...options,
        onSuccess: (response, variables, context) => {
          onSuccess?.(response, variables, context)
          navigate(
            securityCampaignOrgCampaignPath({org: organizationLogin, securityCampaignNumber: response.campaignNumber}),
          )
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
          organizationLogin={organizationLogin}
          setIsOpen={setIsCreationDialogOpen}
          allowDueDateInPast={false}
          submitForm={handleSubmit}
          isPending={isPending}
          formError={error}
          resetForm={reset}
          dialogTitle={templateName ? `New campaign from ${templateName} template` : 'New campaign'}
          alertsLimitReached={alertsCount > maxAlerts}
          maxAlerts={maxAlerts}
          maxManagers={maxManagers}
          templateName={templateName}
          templateDescription={templateDescription}
          currentUser={currentUser}
          query={query}
          bestPracticeCampaignsDocsUrl={bestPracticeCampaignsDocsUrl}
          showAutofixPullRequests={showAutofixPullRequests ?? false}
          showGenerateIssues={showGenerateIssues ?? false}
          campaignsGAEnabled={campaignsGAEnabled ?? false}
          campaign={sourceCampaign}
        />
      )}
    </>
  )
}
