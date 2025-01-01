import {Banner, Dialog} from '@primer/react/experimental'
import {useCallback, useState} from 'react'
import {useConfirmCopilotPlanChange} from '../../hooks/use-confirm-copilot-plan-change'
import {useNavigate} from '@github-ui/use-navigate'
import styles from './CopilotOrganizationDowngradePlanDialog.module.css'
import {clsx} from 'clsx'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import {Button} from '@primer/react'
import {capitalizePlan} from '../../utils/string-utils'

interface CopilotOrganizationDowngradePlanDialogProps {
  oldPlan: string
  newPlan: string
  orgId: number
  closeDialog: () => void
}

export const CopilotOrganizationDowngradePlanDialog = ({
  oldPlan,
  newPlan,
  orgId,
  closeDialog,
}: CopilotOrganizationDowngradePlanDialogProps) => {
  const navigate = useNavigate()
  const {basePath} = useNavigation()

  const handleCloseDialog = useCallback(() => {
    closeDialog()
  }, [closeDialog])
  const [showPlanChangeError, setShowPlanChangeError] = useState(false)

  const handleConfirmClick = useConfirmCopilotPlanChange(
    newPlan,
    orgId,
    basePath,
    () => {
      handleCloseDialog()
      navigate(`${basePath}/enterprise_licensing/copilot`)
    },
    () => {
      setShowPlanChangeError(true)
    },
  )

  return (
    <Dialog
      className={clsx(styles.downgradeConfirmationDialog)}
      onClose={handleCloseDialog}
      title="Downgrade organization access"
    >
      {showPlanChangeError && (
        <Banner
          title="Copilot plan change error"
          hideTitle
          variant="critical"
          onDismiss={() => setShowPlanChangeError(false)}
          className="mb-3"
          data-testid="copilot-plan-change-error-banner"
        >
          {'An error occurred while updating the Copilot plan for this organization.'}
        </Banner>
      )}
      <p className={styles.downgradeConfirmationText} data-testid="copilot-downgrade-confirm-dialog">
        {newPlan === 'disabled' ? (
          <>Do you want to disable Copilot for this organization?</>
        ) : (
          <>Do you want to downgrade this organization to Copilot {capitalizePlan(newPlan)}?</>
        )}
        <span className={clsx('pb-3', styles.downgradeConfirmationSubtext)}>This will:</span>
        {newPlan === 'disabled' ? (
          <>Remove Copilot {capitalizePlan(oldPlan)} licenses.</>
        ) : (
          <>
            Downgrade Copilot {capitalizePlan(oldPlan)} licenses to Copilot {capitalizePlan(newPlan)}.
          </>
        )}
      </p>
      <p className={'color-fg-muted pb-2'}>Users will lose access to Copilot {capitalizePlan(oldPlan)} immediately.</p>
      <div className={styles.dialogActions}>
        <Button variant="default" onClick={handleCloseDialog}>
          Cancel
        </Button>
        <Button variant="danger" onClick={handleConfirmClick}>
          {newPlan === 'disabled' ? <>Remove licenses</> : <>Downgrade licenses</>}
        </Button>
      </div>
    </Dialog>
  )
}
