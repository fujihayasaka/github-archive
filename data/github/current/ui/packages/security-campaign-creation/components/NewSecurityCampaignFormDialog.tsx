import {Box, Link, UnderlineNav} from '@primer/react'
import {SecurityCampaignFormContents} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormContents'
import {SecurityCampaignFormDialogInner} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormDialogInner'
import {SecurityCampaignFormWrapper} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormWrapper'
import type {SecurityCampaign, SecurityCampaignForm} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import type {User} from '@github-ui/security-campaigns-shared/types/user'
import type {MutateOptions} from '@github-ui/react-query'
import {useMemo, useState, type ReactNode} from 'react'
import {useAlertsSummaryQuery} from '@github-ui/security-campaigns-shared/hooks/use-alerts-summary-query'
import {RepositoriesPanel} from '@github-ui/security-campaigns-shared/components/RepositoriesPanel'
import {FiltersPanel} from '@github-ui/security-campaigns-shared/components/FiltersPanel'
import {Banner} from '@primer/react/experimental'
import {
  CampaignDialogTabContentHeight,
  CampaignDialogTabs,
  type CampaignDialogTab,
} from '@github-ui/security-campaigns-shared/types/campaign-dialog-tab'
import {securityCampaignOrgCampaignAlertsSummaryPath} from '@github-ui/paths'

export interface NewSecurityCampaignFormDialogProps {
  organizationLogin: string
  setIsOpen: (isOpen: boolean) => void
  campaign: SecurityCampaign | null
  currentUser: User
  allowDueDateInPast: boolean
  submitForm: (campaign: SecurityCampaignForm, options: MutateOptions<unknown, Error, unknown>) => void
  isPending: boolean
  formError: Error | null
  resetForm: () => void

  dialogTitle: ReactNode

  alertsLimitReached: boolean
  maxAlerts: number
  maxManagers: number

  query: string

  // Used when creating a campaign from a template.
  templateName?: string
  templateDescription?: string

  bestPracticeCampaignsDocsUrl: string
  showAutofixPullRequests: boolean
  showGenerateIssues: boolean
  campaignsGAEnabled: boolean
}

export function NewSecurityCampaignFormDialog({
  organizationLogin,
  setIsOpen,
  campaign,
  currentUser,
  allowDueDateInPast,
  submitForm,
  isPending,
  formError,
  resetForm,
  dialogTitle,
  alertsLimitReached,
  maxAlerts,
  maxManagers,
  query,
  templateName,
  templateDescription,
  bestPracticeCampaignsDocsUrl,
  showAutofixPullRequests,
  showGenerateIssues,
  campaignsGAEnabled,
}: NewSecurityCampaignFormDialogProps) {
  const [selectedTab, setSelectedTab] = useState<CampaignDialogTab>(CampaignDialogTabs.General)

  const handleSubmitForm = async (newCampaign: SecurityCampaignForm) => {
    submitForm(newCampaign, {
      onSuccess: () => setIsOpen(false),
    })
  }

  const {
    data,
    isPending: isSummaryPending,
    error,
  } = useAlertsSummaryQuery(securityCampaignOrgCampaignAlertsSummaryPath({org: organizationLogin}), {
    query,
  })

  let formHeight = CampaignDialogTabContentHeight
  if (showAutofixPullRequests) {
    formHeight += 80
  }
  if (showGenerateIssues) {
    formHeight += 80
  }

  const initialValues = useMemo(() => {
    if (campaign) {
      return {...campaign, managers: [currentUser], endsAt: ''}
    }
    if (templateName && templateDescription) {
      return {
        name: templateName,
        description: templateDescription,
        endsAt: null,
        managers: [currentUser],
        teamManagers: [],
        contactLink: null,
      }
    }
    return undefined
  }, [campaign, currentUser, templateDescription, templateName])

  return (
    <SecurityCampaignFormWrapper
      initialValues={initialValues}
      currentUser={currentUser}
      allowDueDateInPast={allowDueDateInPast}
      maxManagers={maxManagers}
      submitForm={handleSubmitForm}
      reset={resetForm}
      isPending={isPending}
      formError={formError}
    >
      <SecurityCampaignFormDialogInner
        dialogTitle={dialogTitle}
        setIsOpen={setIsOpen}
        submitButtonText={alertsLimitReached ? 'Continue creating a campaign' : 'Create campaign'}
        cancelButtonText={alertsLimitReached ? 'Back to filters' : 'Cancel'}
      >
        {alertsLimitReached && (
          <Box sx={{mb: 2}}>
            <Banner
              title="This looks like a big campaign"
              description={
                <>
                  {`Campaigns can include up to ${maxAlerts} alerts. The current list
                        of alerts exceeds the campaign limit, consider editing your filters to reduce the list of alerts. `}
                  {bestPracticeCampaignsDocsUrl && (
                    <Link inline href={bestPracticeCampaignsDocsUrl}>
                      Learn more about optimizing security campaigns.
                    </Link>
                  )}
                </>
              }
            />
          </Box>
        )}

        <UnderlineNav aria-label="Select a tab" loadingCounters={isSummaryPending}>
          <UnderlineNav.Item
            aria-current={selectedTab === CampaignDialogTabs.General ? 'location' : undefined}
            onSelect={() => setSelectedTab(CampaignDialogTabs.General)}
          >
            General
          </UnderlineNav.Item>
          {campaignsGAEnabled && (
            <UnderlineNav.Item
              counter={query.split(' ').length}
              aria-current={selectedTab === CampaignDialogTabs.Filters ? 'location' : undefined}
              onSelect={() => setSelectedTab(CampaignDialogTabs.Filters)}
            >
              Filters
            </UnderlineNav.Item>
          )}
          <UnderlineNav.Item
            counter={data?.repositories.length ?? 0}
            aria-current={selectedTab === CampaignDialogTabs.Repositories ? 'location' : undefined}
            onSelect={() => setSelectedTab(CampaignDialogTabs.Repositories)}
          >
            Repositories
          </UnderlineNav.Item>
        </UnderlineNav>
        <Box sx={{height: formHeight}}>
          {selectedTab === CampaignDialogTabs.General && (
            <Box sx={{paddingTop: 2}}>
              <SecurityCampaignFormContents
                organizationLogin={organizationLogin}
                maxManagers={maxManagers}
                showAutofixPullRequests={showAutofixPullRequests}
                showGenerateIssues={showGenerateIssues}
              />
            </Box>
          )}
          {campaignsGAEnabled && selectedTab === CampaignDialogTabs.Filters && <FiltersPanel query={query} />}
          {selectedTab === CampaignDialogTabs.Repositories && (
            <RepositoriesPanel alertsSummary={data} isSummaryPending={isSummaryPending} error={error} />
          )}
        </Box>
      </SecurityCampaignFormDialogInner>
    </SecurityCampaignFormWrapper>
  )
}
