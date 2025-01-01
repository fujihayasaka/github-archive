import {Dialog} from '@primer/react/experimental'
import {useCallback} from 'react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useNavigate} from '@github-ui/use-navigate'
import styles from '../CopilotDangerZone.module.css'
import {clsx} from 'clsx'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'

interface CopilotOrganizationDisableAllAccessDialogProps {
  closeDialog: () => void
}

export const CopilotOrganizationDisableAllAccessDialog = ({
  closeDialog,
}: CopilotOrganizationDisableAllAccessDialogProps) => {
  const navigate = useNavigate()

  const {slug, basePath} = useNavigation()

  const handleCloseDialog = useCallback(() => {
    closeDialog()
  }, [closeDialog])

  const handleConfirmClick = async () => {
    const data = new FormData()
    data.append('copilot_enabled', 'disabled')
    await verifiedFetch(`${basePath}/settings/update_copilot_enablement`, {
      method: 'PUT',
      body: data,
    })
    handleCloseDialog()
    navigate(`${basePath}/enterprise_licensing`)
  }

  return (
    <Dialog
      className={clsx(styles.dangerZoneDialog)}
      onClose={handleCloseDialog}
      title="Disable all enterprise Copilot access"
      footerButtons={[
        {buttonType: 'default', content: 'Cancel', onClick: handleCloseDialog},
        {
          buttonType: 'danger',
          onClick: handleConfirmClick,
          content: 'Disable Copilot',
        },
      ]}
    >
      {
        <p className={styles.dangerZoneText} data-testid="copilot-danger-zone-dialog">
          Are you sure you want to disable all Copilot access for the entire {slug} enterprise? All members will lose
          access immediately and all organizations&apos; Copilot settings will be deleted.
        </p>
      }
    </Dialog>
  )
}
