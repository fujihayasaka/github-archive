import {Box, Link, UnderlineNav} from '@primer/react'
import {SecurityCampaignFormContents} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormContents'
import {SecurityCampaignFormDialogInner} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormDialogInner'
import {SecurityCampaignFormWrapper} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormWrapper'
import type {SecurityCampaign, SecurityCampaignForm} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import type {User} from '@github-ui/security-campaigns-shared/types/user'
import type {MutateOptions} from '@tanstack/react-query'
import {useState, type ReactNode} from 'react'
import {useAlertsSummaryQuery} from '../hooks/use-alerts-summary-query'
import {RepositoriesPanel} from './RepositoriesPanel'
import {Banner} from '@primer/react/experimental'

enum SelectedTab {
  General = 'general',
  Repositories = 'repositories',
}

export interface NewSecurityCampaignFormDialogProps {
  setIsOpen: (isOpen: boolean) => void
  campaign?: SecurityCampaign
  currentUser?: User
  allowDueDateInPast: boolean
  submitForm: (campaign: SecurityCampaignForm, options: MutateOptions<unknown, Error, unknown>) => void
  isPending: boolean
  formError: Error | null
  resetForm: () => void

  dialogTitle: ReactNode

  alertsLimitReached: boolean
  maxAlerts: number
  maxRepos: number

  query: string
  campaignManagersPath: string
  campaignAlertsSummaryPath: string

  // Used when creating a campaign from a template.
  templateName?: string
  templateDescription?: string

  bestPracticeCampaignsDocsUrl: string
  showAutofixPullRequests: boolean
}

export function NewSecurityCampaignFormDialog({
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
  maxRepos,
  query,
  campaignManagersPath,
  campaignAlertsSummaryPath,
  templateName,
  templateDescription,
  bestPracticeCampaignsDocsUrl,
  showAutofixPullRequests,
}: NewSecurityCampaignFormDialogProps) {
  const [selectedTab, setSelectedTab] = useState<SelectedTab>(SelectedTab.General)

  const handleSubmitForm = async (newCampaign: SecurityCampaignForm) => {
    submitForm(newCampaign, {
      onSuccess: () => setIsOpen(false),
    })
  }

  const {data, isPending: isSummaryPending} = useAlertsSummaryQuery(campaignAlertsSummaryPath, {
    query,
  })

  return (
    <SecurityCampaignFormWrapper
      campaign={campaign}
      currentUser={currentUser}
      allowDueDateInPast={allowDueDateInPast}
      submitForm={handleSubmitForm}
      reset={resetForm}
      isPending={isPending}
      formError={formError}
      templateName={templateName}
      templateDescription={templateDescription}
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
                  Campaigns can include up to {maxAlerts} alerts spread across up to {maxRepos} repos. The current list
                  of alerts exceeds the campaign limit, consider editing your filters to reduce the list of alerts.{' '}
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
            aria-current={selectedTab === SelectedTab.General ? 'location' : undefined}
            onSelect={() => setSelectedTab(SelectedTab.General)}
          >
            General
          </UnderlineNav.Item>
          <UnderlineNav.Item
            counter={data?.repositories.length ?? 0}
            aria-current={selectedTab === SelectedTab.Repositories ? 'location' : undefined}
            onSelect={() => setSelectedTab(SelectedTab.Repositories)}
          >
            Repositories
          </UnderlineNav.Item>
        </UnderlineNav>
        <Box sx={{height: showAutofixPullRequests ? 510 : 430}}>
          {selectedTab === SelectedTab.General && (
            <Box sx={{paddingTop: 2}}>
              <SecurityCampaignFormContents
                campaignManagersPath={campaignManagersPath}
                showAutofixPullRequests={showAutofixPullRequests}
              />
            </Box>
          )}
          {selectedTab === SelectedTab.Repositories && (
            <RepositoriesPanel alertsSummary={data} isSummaryPending={isSummaryPending} />
          )}
        </Box>
      </SecurityCampaignFormDialogInner>
    </SecurityCampaignFormWrapper>
  )
}
