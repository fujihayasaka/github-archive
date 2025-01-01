import type {MutateOptions} from '@github-ui/react-query'
import {useState} from 'react'
import {Stack, UnderlineNav} from '@primer/react'
import {securityCampaignOrgRepositoriesSummaryPath} from '@github-ui/paths'
import type {SecurityCampaign, SecurityCampaignForm} from '../types/security-campaign'
import {useAlertsSummaryQuery} from '../hooks/use-alerts-summary-query'
import {type CampaignDialogTab, CampaignDialogTabs, CampaignDialogTabContentHeight} from '../types/campaign-dialog-tab'
import {FiltersPanel} from './FiltersPanel'
import {RepositoriesPanel} from './RepositoriesPanel'
import {SecurityCampaignFormContents} from './SecurityCampaignFormContents'
import {SecurityCampaignFormDialogInner} from './SecurityCampaignFormDialogInner'
import {SecurityCampaignFormWrapper} from './SecurityCampaignFormWrapper'

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
        <>
          <UnderlineNav aria-label="Select a tab">
            <UnderlineNav.Item
              aria-current={selectedTab === CampaignDialogTabs.General ? 'location' : undefined}
              onSelect={e => {
                e.preventDefault()
                setSelectedTab(CampaignDialogTabs.General)
              }}
            >
              General
            </UnderlineNav.Item>
            <UnderlineNav.Item
              counter={campaign.creationQuery?.split(' ').length ?? 0}
              aria-current={selectedTab === CampaignDialogTabs.Filters ? 'location' : undefined}
              onSelect={e => {
                e.preventDefault()
                setSelectedTab(CampaignDialogTabs.Filters)
              }}
            >
              Filters
            </UnderlineNav.Item>
            <UnderlineNav.Item
              counter={data?.repositories.length ?? 0}
              aria-current={selectedTab === CampaignDialogTabs.Repositories ? 'location' : undefined}
              onSelect={e => {
                e.preventDefault()
                setSelectedTab(CampaignDialogTabs.Repositories)
              }}
            >
              Repositories
            </UnderlineNav.Item>
          </UnderlineNav>
          <Stack style={{height: CampaignDialogTabContentHeight}}>
            {selectedTab === CampaignDialogTabs.General && (
              <Stack className="pt-2">
                <SecurityCampaignFormContents
                  organizationLogin={organizationLogin}
                  maxManagers={maxManagers}
                  readOnly={readOnly}
                />
              </Stack>
            )}
            {selectedTab === CampaignDialogTabs.Filters && <FiltersPanel query={campaign.creationQuery} />}
            {selectedTab === CampaignDialogTabs.Repositories && (
              <RepositoriesPanel alertsSummary={data} isSummaryPending={isSummaryPending} error={error} />
            )}
          </Stack>
        </>
      </SecurityCampaignFormDialogInner>
    </SecurityCampaignFormWrapper>
  )
}
