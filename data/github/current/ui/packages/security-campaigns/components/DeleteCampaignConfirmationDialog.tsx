import {Dialog} from '@primer/react/experimental'
import {useCallback} from 'react'

export type DeleteCampaignConfirmationDialogProps = {
  setIsOpen: (isOpen: boolean) => void
  deleteCampaign: () => void
  disabled: boolean
  isDraft: boolean
  campaignName: string
}

export const DeleteCampaignConfirmationDialog = ({
  setIsOpen,
  deleteCampaign,
  disabled,
  isDraft = false,
  campaignName,
}: DeleteCampaignConfirmationDialogProps) => {
  const onDialogClose = useCallback(() => {
    setIsOpen(false)
  }, [setIsOpen])

  return (
    <Dialog
      title={isDraft ? 'Delete draft campaign?' : 'Delete campaign?'}
      onClose={onDialogClose}
      width="large"
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: () => setIsOpen(false),
          disabled,
        },
        {
          buttonType: 'danger',
          content: 'Delete',
          onClick: () => deleteCampaign(),
          disabled,
        },
      ]}
    >
      {isDraft ? (
        <span>
          Are you sure you want to delete the draft campaign <strong>{campaignName}</strong>?<br />
          This action cannot be undone.
        </span>
      ) : (
        <span>Deleting a campaign is a permanent action. Are you sure you want to delete this campaign?</span>
      )}
    </Dialog>
  )
}
