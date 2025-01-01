import {useMemo} from 'react'
import type {SecurityCampaignForm, SecurityCampaign} from '../types/security-campaign'
import type {User} from '../types/user'
import {SecurityCampaignFormContents} from './SecurityCampaignFormContents'
import {SecurityCampaignFormDialogInner} from './SecurityCampaignFormDialogInner'
import {SecurityCampaignFormWrapper} from './SecurityCampaignFormWrapper'

export interface UpsertDraftSecurityCampaignFormDialogProps {
  organizationLogin: string
  currentUser: User
  setIsOpen: (isOpen: boolean) => void
  submitForm: (campaign: SecurityCampaignForm) => void
  isPending: boolean
  formError: Error | null
  resetForm: () => void
  maxManagers: number
  campaign?: SecurityCampaign
  campaignName?: string | null
  campaignDescription?: string | null
}

export function UpsertDraftSecurityCampaignFormDialog({
  organizationLogin,
  currentUser,
  setIsOpen,
  submitForm,
  isPending,
  formError,
  resetForm,
  maxManagers,
  campaign,
  campaignName,
  campaignDescription,
}: UpsertDraftSecurityCampaignFormDialogProps) {
  const handleSubmitForm = async (newCampaign: SecurityCampaignForm) => {
    submitForm(newCampaign)
  }

  const title = campaign ? 'Edit draft campaign' : 'New draft campaign from filters'

  const campaignInitialValues = useMemo(() => {
    if (campaign) return campaign

    return {
      name: campaignName || '',
      description: campaignDescription || '',
      endsAt: null,
      managers: [currentUser],
      teamManagers: [],
      contactLink: null,
    }
  }, [campaign, campaignDescription, campaignName, currentUser])

  return (
    <SecurityCampaignFormWrapper
      initialValues={campaignInitialValues}
      currentUser={currentUser}
      maxManagers={maxManagers}
      allowDueDateInPast={false}
      submitForm={handleSubmitForm}
      reset={resetForm}
      isPending={isPending}
      formError={formError}
      descriptionDisplayMode="optional"
      dueDateDisplayMode="hidden"
    >
      <SecurityCampaignFormDialogInner
        setIsOpen={setIsOpen}
        dialogTitle={title}
        submitButtonText="Save draft"
        cancelButtonText="Cancel"
      >
        <SecurityCampaignFormContents organizationLogin={organizationLogin} maxManagers={maxManagers} />
      </SecurityCampaignFormDialogInner>
    </SecurityCampaignFormWrapper>
  )
}
