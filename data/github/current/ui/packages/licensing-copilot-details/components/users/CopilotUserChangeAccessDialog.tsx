import {Banner, Dialog} from '@primer/react/experimental'
import {useState} from 'react'
import {useNavigate} from '@github-ui/use-navigate'
import styles from './CopilotUserChangeAccessDialog.module.css'
import {clsx} from 'clsx'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import {Button} from '@primer/react'
import {verifiedFetch} from '@github-ui/verified-fetch'

interface CopilotUserChangeAccessDialogProps {
  users: number[]
  downgrade: boolean
  onClose: () => void
}

export const CopilotUserChangeAccessDialog = ({users, downgrade, onClose}: CopilotUserChangeAccessDialogProps) => {
  const navigate = useNavigate()
  const {basePath} = useNavigation()

  const [showPlanChangeError, setShowPlanChangeError] = useState(false)

  const handleLicenseChange = async (userIDs: number[]) => {
    const formData = new FormData()
    for (const userID of userIDs) {
      formData.append('users[]', userID.toString())
    }

    const endpoint = downgrade
      ? `${basePath}/enterprise_licensing/unassign_user_licenses`
      : `${basePath}/enterprise_licensing/assign_user_licenses`

    try {
      const response = await verifiedFetch(endpoint, {
        method: downgrade ? 'DELETE' : 'POST',
        body: formData,
      })
      if (response.ok) {
        onClose()
        navigate(`${basePath}/enterprise_licensing/copilot?tab=users`)
      } else {
        setShowPlanChangeError(true)
      }
    } catch {
      setShowPlanChangeError(true)
    }
  }

  return (
    <Dialog
      className={clsx(styles.changeConfirmationDialog)}
      onClose={onClose}
      title={downgrade ? 'Remove Copilot Business licenses' : 'Assign Copilot Business licenses'}
    >
      {showPlanChangeError && (
        <Banner
          title="Copilot license change error"
          hideTitle
          variant="critical"
          onDismiss={() => setShowPlanChangeError(false)}
          className="mb-3"
          data-testid="copilot-license-change-error-banner"
        >
          {'An error occurred while updating the Copilot licenses for this enterprise.'}
        </Banner>
      )}
      <div className={styles.changeConfirmationText} data-testid="copilot-license-change-dialog">
        <span>
          Do you want to <span>{downgrade ? 'remove' : 'assign'}</span> <span>{users.length}</span> Copilot Business
          licenses?
        </span>
        {downgrade === true ? (
          <>
            <p className={'color-fg-muted pb-2 pt-4'}>Users will lose access at the end of the billing cycle.</p>
            {/** TODO add count for user licenses that will be unaffected. Also add the date above. */}
          </>
        ) : (
          <>
            <p className={'color-fg-muted pb-2 pt-4'}>Users will gain access immediately.</p>
            {/** TODO add count for user licenses that are already present */}
          </>
        )}
      </div>
      <div className={styles.dialogActions}>
        <Button variant="default" onClick={onClose}>
          Cancel
        </Button>
        <Button variant={downgrade ? 'danger' : 'primary'} onClick={() => handleLicenseChange(users)}>
          {downgrade === true ? <>Remove licenses</> : <>Add licenses</>}
        </Button>
      </div>
    </Dialog>
  )
}
