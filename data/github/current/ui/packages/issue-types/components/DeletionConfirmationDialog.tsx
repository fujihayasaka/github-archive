import {FormControl, TextInput} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {useCallback, useState} from 'react'
import {Resources} from '../constants/strings'
import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {DeletionConfirmationDialogIssueType$key} from './__generated__/DeletionConfirmationDialogIssueType.graphql'
import {useDeleteIssueType} from '../hooks/use-delete-issue-type'
import {useIssueTypesAnalytics} from '../hooks/use-issue-types-analytics'
import type {SetA11yAnnouncement} from '../types/shared-types'

type DeletionConfirmationDialogProps = {
  issueType: DeletionConfirmationDialogIssueType$key
  owner: string
  organizationId?: string
  closeDialog: () => void
  returnFocusRefDeletion: React.RefObject<HTMLButtonElement>
  redirectOnDeletion?: boolean
  setA11yAnnouncement?: SetA11yAnnouncement
}

export const DeletionConfirmationDialog = ({
  closeDialog,
  issueType,
  owner,
  organizationId,
  returnFocusRefDeletion,
  redirectOnDeletion = true,
  setA11yAnnouncement,
}: DeletionConfirmationDialogProps): JSX.Element => {
  const data = useFragment<DeletionConfirmationDialogIssueType$key>(
    graphql`
      fragment DeletionConfirmationDialogIssueType on IssueType {
        id
        name
      }
    `,
    issueType,
  )
  const [confirmationText, setConfirmationText] = useState<string | null>(null)
  const {deleteIssueType} = useDeleteIssueType()
  const {sendIssueTypesAnalyticsEvent} = useIssueTypesAnalytics()

  const handleSuccess = useCallback(() => {
    setA11yAnnouncement?.(Resources.deletedIssueTypeSuccess)
  }, [setA11yAnnouncement])

  const handleCloseDialog = useCallback(
    (isDeleting: boolean) => {
      setA11yAnnouncement?.(null)
      closeDialog()
      setTimeout(() => {
        if (isDeleting || !returnFocusRefDeletion?.current) {
          const createButtonElement = document.getElementById('create-issue-type')
          createButtonElement?.focus()
        } else {
          returnFocusRefDeletion.current.focus()
        }
      }, 0)
    },
    [closeDialog, returnFocusRefDeletion, setA11yAnnouncement],
  )

  const handleDeleteClick = useCallback(() => {
    handleCloseDialog(true)
    deleteIssueType(data.id, owner, organizationId, handleSuccess, redirectOnDeletion)
    sendIssueTypesAnalyticsEvent('org_issue_type.delete', 'ORG_ISSUE_TYPE_DELETE_BUTTON', {issueTypeId: data.id})
  }, [
    handleCloseDialog,
    deleteIssueType,
    data.id,
    organizationId,
    owner,
    handleSuccess,
    sendIssueTypesAnalyticsEvent,
    redirectOnDeletion,
  ])

  return (
    <Dialog
      sx={{
        width: '35%',
        maxHeight: 'clamp(256px, 80vh, 100vh)',
      }}
      onClose={() => handleCloseDialog(false)}
      aria-labelledby="header-id"
      title={Resources.deleteDialogHeader}
      footerButtons={[
        {buttonType: 'default', content: Resources.cancelButton, onClick: () => handleCloseDialog(false)},
        {
          buttonType: 'danger',
          content: Resources.deleteButton,
          onClick: handleDeleteClick,
          disabled: confirmationText !== data.name,
          name: 'dialog-delete',
        },
      ]}
    >
      <span>{Resources.deleteDialogBody(data.name)}</span>
      <FormControl id="delete-type-confirmation" required>
        <FormControl.Label sx={{pt: 3}}>{`Please type "${data.name}" to confirm`}</FormControl.Label>
        <TextInput
          sx={{width: '100%'}}
          data-testid="deletion-confirmation-dialog-name"
          onChange={e => setConfirmationText(e.target.value)}
        />
      </FormControl>
    </Dialog>
  )
}
