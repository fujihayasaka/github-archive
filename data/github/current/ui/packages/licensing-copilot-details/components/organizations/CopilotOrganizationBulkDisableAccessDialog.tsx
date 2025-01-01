import {Banner, Dialog} from '@primer/react/experimental'
import {useCallback, useState} from 'react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useNavigate} from '@github-ui/use-navigate'
import styles from './CopilotOrganizationDowngradePlanDialog.module.css'
import {clsx} from 'clsx'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import {Button} from '@primer/react'

interface CopilotOrganizationBulkDisableAccessDialogProps {
  orgIds: number[]
  closeDialog: () => void
}

export const CopilotOrganizationBulkDisableAccessDialog = ({
  orgIds,
  closeDialog,
}: CopilotOrganizationBulkDisableAccessDialogProps) => {
  const navigate = useNavigate()
  const {basePath} = useNavigation()
  const [showDisableError, setShowDisableError] = useState(false)

  const handleCloseDialog = useCallback(() => {
    closeDialog()
  }, [closeDialog])

  const handleConfirmClick = async () => {
    const formData = new FormData()
    formData.append('enablement', 'disable')
    for (const orgId of orgIds) {
      formData.append('organizations[]', orgId.toString())
    }
    try {
      const response = await verifiedFetch(`${basePath}/settings/update_copilot_bulk_org_enablement`, {
        method: 'PUT',
        body: formData,
      })
      if (response.ok) {
        handleCloseDialog()
        navigate(`${basePath}/enterprise_licensing/copilot`)
      } else {
        setShowDisableError(true)
      }
    } catch {
      setShowDisableError(true)
    }
  }

  return (
    <Dialog
      className={clsx(styles.downgradeConfirmationDialog)}
      onClose={handleCloseDialog}
      title="Disable organization access"
    >
      {showDisableError && (
        <Banner
          title="Copilot disablement error"
          hideTitle
          variant="critical"
          onDismiss={() => setShowDisableError(false)}
          className="mb-3"
          data-testid="copilot-disablement-error-banner"
        >
          {'An error occurred while disabling Copilot for your organizations.'}
        </Banner>
      )}
      <p className={styles.downgradeConfirmationText} data-testid="copilot-bulk-disable-confirm-dialog">
        Do you want to disable Copilot for {orgIds.length} organization(s)? Organizations&apos; Copilot settings will be
        saved.
        <span className={clsx('pb-3', styles.downgradeConfirmationSubtext)}>This will:</span>
        Remove Copilot licenses.
      </p>
      <p className={'color-fg-muted pb-2'}>
        All members will lose access immediately, even if they have access from another source.
      </p>
      <div className={styles.dialogActions}>
        <Button variant="default" onClick={handleCloseDialog}>
          Cancel
        </Button>
        <Button variant="danger" onClick={handleConfirmClick}>
          Disable Copilot
        </Button>
      </div>
    </Dialog>
  )
}
