import type {SecurityCampaign, SecurityCampaignForm} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import type {MutateOptions} from '@github-ui/react-query'
import {SecurityCampaignFormWrapper} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormWrapper'
import {SecurityCampaignFormDialogInner} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormDialogInner'
import {SecurityCampaignFormContents} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormContents'
import {useState} from 'react'
import {Box, UnderlineNav} from '@primer/react'
import {useAlertsSummaryQuery} from '@github-ui/security-campaigns-shared/hooks/use-alerts-summary-query'
import {RepositoriesPanel} from '@github-ui/security-campaigns-shared/components/RepositoriesPanel'
import {
  CampaignDialogTabContentHeight,
  CampaignDialogTabs,
  type CampaignDialogTab,
} from '@github-ui/security-campaigns-shared/types/campaign-dialog-tab'
import {FiltersPanel} from '@github-ui/security-campaigns-shared/components/FiltersPanel'
import {securityCampaignOrgRepositoriesSummaryPath} from '@github-ui/paths'

export interface EditSecurityCampaignFormDialogProps {
  organizationLogin: string
  securityCampaignNumber: number
  setIsOpen: (isOpen: boolean) => void
  campaign: SecurityCampaign
  submitForm: (campaign: SecurityCampaignForm, options: MutateOptions<unknown, Error, unknown>) => void
  isPending: boolean
  formError: Error | null
  resetForm: () => void
  maxManagers: number
  campaignsGAEnabled: boolean
  readOnly: boolean
}

export function EditSecurityCampaignFormDialog({
  organizationLogin,
  securityCampaignNumber,
  setIsOpen,
  campaign,
  submitForm,
  isPending,
  formError,
  resetForm,
  maxManagers,
  campaignsGAEnabled,
  readOnly,
}: EditSecurityCampaignFormDialogProps) {
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
  } = useAlertsSummaryQuery(
    securityCampaignOrgRepositoriesSummaryPath({org: organizationLogin, securityCampaignNumber}),
    {},
    {enabled: campaignsGAEnabled},
  )

  return (
    <SecurityCampaignFormWrapper
      initialValues={campaign}
      currentUser={undefined} // The default will always be the campaign manager
      allowDueDateInPast
      maxManagers={maxManagers}
      submitForm={handleSubmitForm}
      reset={resetForm}
      isPending={isPending}
      formError={formError}
    >
      <SecurityCampaignFormDialogInner
        setIsOpen={setIsOpen}
        dialogTitle={readOnly ? 'Campaign details' : 'Edit campaign'}
        submitButtonText="Save changes"
        cancelButtonText={readOnly ? 'Close' : 'Cancel'}
        hideSubmitButton={readOnly}
      >
        {campaignsGAEnabled && (
          <>
            <UnderlineNav aria-label="Select a tab">
              <UnderlineNav.Item
                aria-current={selectedTab === CampaignDialogTabs.General ? 'location' : undefined}
                onSelect={() => setSelectedTab(CampaignDialogTabs.General)}
              >
                General
              </UnderlineNav.Item>
              <UnderlineNav.Item
                counter={campaign.creationQuery?.split(' ').length ?? 0}
                aria-current={selectedTab === CampaignDialogTabs.Filters ? 'location' : undefined}
                onSelect={() => setSelectedTab(CampaignDialogTabs.Filters)}
              >
                Filters
              </UnderlineNav.Item>
              <UnderlineNav.Item
                counter={data?.repositories.length ?? 0}
                aria-current={selectedTab === CampaignDialogTabs.Repositories ? 'location' : undefined}
                onSelect={() => setSelectedTab(CampaignDialogTabs.Repositories)}
              >
                Repositories
              </UnderlineNav.Item>
            </UnderlineNav>
            <Box sx={{height: CampaignDialogTabContentHeight}}>
              {selectedTab === CampaignDialogTabs.General && (
                <Box sx={{paddingTop: 2}}>
                  <SecurityCampaignFormContents
                    organizationLogin={organizationLogin}
                    maxManagers={maxManagers}
                    readOnly={readOnly}
                  />
                </Box>
              )}
              {selectedTab === CampaignDialogTabs.Filters && <FiltersPanel query={campaign.creationQuery} />}
              {selectedTab === CampaignDialogTabs.Repositories && (
                <RepositoriesPanel alertsSummary={data} isSummaryPending={isSummaryPending} error={error} />
              )}
            </Box>
          </>
        )}

        {!campaignsGAEnabled && (
          <SecurityCampaignFormContents organizationLogin={organizationLogin} maxManagers={maxManagers} />
        )}
      </SecurityCampaignFormDialogInner>
    </SecurityCampaignFormWrapper>
  )
}
