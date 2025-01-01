import type {SecurityCampaign, SecurityCampaignForm} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import type {MutateOptions} from '@tanstack/react-query'
import {SecurityCampaignFormWrapper} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormWrapper'
import {SecurityCampaignFormDialogInner} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormDialogInner'
import {SecurityCampaignFormContents} from '@github-ui/security-campaigns-shared/components/SecurityCampaignFormContents'

export interface EditSecurityCampaignFormDialogProps {
  setIsOpen: (isOpen: boolean) => void
  campaign: SecurityCampaign
  submitForm: (campaign: SecurityCampaignForm, options: MutateOptions<unknown, Error, unknown>) => void
  isPending: boolean
  formError: Error | null
  resetForm: () => void
  campaignManagersPath: string
}

export function EditSecurityCampaignFormDialog({
  setIsOpen,
  campaign,
  submitForm,
  isPending,
  formError,
  resetForm,
  campaignManagersPath,
}: EditSecurityCampaignFormDialogProps) {
  const handleSubmitForm = async (newCampaign: SecurityCampaignForm) => {
    submitForm(newCampaign, {
      onSuccess: () => setIsOpen(false),
    })
  }

  return (
    <SecurityCampaignFormWrapper
      campaign={campaign}
      currentUser={undefined} // The default will always be the campaign manager
      allowDueDateInPast
      submitForm={handleSubmitForm}
      reset={resetForm}
      isPending={isPending}
      formError={formError}
    >
      <SecurityCampaignFormDialogInner
        setIsOpen={setIsOpen}
        dialogTitle="Edit campaign"
        submitButtonText="Save changes"
        cancelButtonText="Cancel"
      >
        <SecurityCampaignFormContents campaignManagersPath={campaignManagersPath} />
      </SecurityCampaignFormDialogInner>
    </SecurityCampaignFormWrapper>
  )
}
