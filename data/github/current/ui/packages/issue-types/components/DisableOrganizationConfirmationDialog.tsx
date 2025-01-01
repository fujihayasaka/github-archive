import {Dialog} from '@primer/react/experimental'
import {Resources} from '../constants/strings'
import {graphql, useFragment} from 'react-relay'
import type {DisableOrganizationConfirmationDialogIssueType$key} from './__generated__/DisableOrganizationConfirmationDialogIssueType.graphql'
import {useEnableDisableIssueType} from '../hooks/use-enable-disable-issue-type'
import {useCallback} from 'react'
import {useIssueTypesAnalytics} from '../hooks/use-issue-types-analytics'
import type {SetA11yAnnouncement} from '../types/shared-types'

interface DisableOrganizationConfirmationDialogProps {
  issueType: DisableOrganizationConfirmationDialogIssueType$key
  closeDialog: () => void
  returnFocusRefDisable?: React.RefObject<HTMLElement>
  setA11yAnnouncement?: SetA11yAnnouncement
}

export const DisableOrganizationConfirmationDialog = ({
  issueType,
  closeDialog,
  returnFocusRefDisable,
  setA11yAnnouncement,
}: DisableOrganizationConfirmationDialogProps) => {
  const {disableOrganizationIssueType} = useEnableDisableIssueType()
  const {sendIssueTypesAnalyticsEvent} = useIssueTypesAnalytics()

  const data = useFragment<DisableOrganizationConfirmationDialogIssueType$key>(
    graphql`
      fragment DisableOrganizationConfirmationDialogIssueType on IssueType {
        id
        name
      }
    `,
    issueType,
  )

  const handleSuccess = useCallback(() => {
    setA11yAnnouncement?.(Resources.disabledIssueTypeSuccess)
  }, [setA11yAnnouncement])

  const handleCloseDialog = useCallback(() => {
    setA11yAnnouncement?.(null)
    closeDialog()
  }, [setA11yAnnouncement, closeDialog])

  const handleConfirmClick = useCallback(() => {
    handleCloseDialog()
    sendIssueTypesAnalyticsEvent('org_issue_type.disable', 'ORG_ISSUE_TYPE_DISABLE_BUTTON', {issueTypeId: data.id})
    disableOrganizationIssueType(data.id, handleSuccess)
  }, [disableOrganizationIssueType, data.id, handleSuccess, sendIssueTypesAnalyticsEvent, handleCloseDialog])

  return (
    <Dialog
      sx={{
        width: '35%',
        maxHeight: 'clamp(256px, 80vh, 100vh)',
      }}
      onClose={handleCloseDialog}
      title={Resources.disableConfirmationDialogHeader}
      footerButtons={[
        {buttonType: 'default', content: Resources.cancelButton, onClick: handleCloseDialog},
        {
          buttonType: 'primary',
          onClick: handleConfirmClick,
          content: Resources.disableButton,
        },
      ]}
      returnFocusRef={returnFocusRefDisable}
    >
      <span>{Resources.disableConfirmationDialogBody(data.name)}</span>
    </Dialog>
  )
}
