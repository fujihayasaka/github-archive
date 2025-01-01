import {Banner, Dialog} from '@primer/react/experimental'
import {useState, useCallback} from 'react'
import {useNavigate} from '@github-ui/use-navigate'
import styles from './CopilotOrganizationUpgradePlanDialog.module.css'
import {clsx} from 'clsx'
import {useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import {Button} from '@primer/react'
import {capitalizePlan} from '../../utils/string-utils'
import {useConfirmCopilotPlanChange} from '../../hooks/use-confirm-copilot-plan-change'

interface CopilotOrganizationUpgradePlanDialogProps {
  oldPlan: string
  newPlan: string
  orgId: number
  closeDialog: () => void
}

export const CopilotOrganizationUpgradePlanDialog = ({
  oldPlan,
  newPlan,
  orgId,
  closeDialog,
}: CopilotOrganizationUpgradePlanDialogProps) => {
  const navigate = useNavigate()
  const {basePath} = useNavigation()

  const [showPlanChangeError, setShowPlanChangeError] = useState(false)

  const handleCloseDialog = useCallback(() => {
    closeDialog()
  }, [closeDialog])

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
      className={clsx(styles.upgradeConfirmationDialog)}
      onClose={handleCloseDialog}
      title="Upgrade organization access"
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
      <p className={styles.upgradeConfirmationText} data-testid="copilot-upgrade-confirm-dialog">
        Do you want to upgrade this organization to Copilot {capitalizePlan(newPlan)}?
        <span className={clsx('pb-3', styles.upgradeConfirmationSubtext)}>This will:</span>
        {oldPlan === 'disabled' ? (
          <>Purchase Copilot {capitalizePlan(newPlan)} licenses.</>
        ) : (
          <>
            Upgrade Copilot {capitalizePlan(oldPlan)} licenses to Copilot {capitalizePlan(newPlan)}.
          </>
        )}
      </p>
      <p className={'color-fg-muted pb-2'}>Users will gain access immediately.</p>
      <div className={styles.dialogActions}>
        <Button variant="default" onClick={handleCloseDialog}>
          Cancel
        </Button>
        <Button variant="primary" onClick={handleConfirmClick}>
          {oldPlan === 'disabled' ? <>Purchase licenses</> : <>Upgrade licenses</>}
        </Button>
      </div>
    </Dialog>
  )
}
