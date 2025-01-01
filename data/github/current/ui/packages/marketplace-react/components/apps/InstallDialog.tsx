import {Dialog, Stack} from '@primer/react'
import type {PlanInfo} from '../../types'
import {useMemo, useState} from 'react'
import {PlanForm} from './pricing-plans/PlanForm'
import type {AppListing} from '@github-ui/marketplace-common'
import {InstallButton} from './pricing-plans/InstallButton'
import PlansRadioGroup from './pricing-plans/PlansRadioGroup'
import PlanFormAccountSelector from './pricing-plans/form/PlanFormAccountSelector'
import PlanFormSeatsField from './pricing-plans/form/PlanFormSeatsField'

interface InstallDialogProps {
  planInfo: PlanInfo
  app: AppListing
  open: boolean
  selectedAccount?: string
  setSelectedAccount: (account: string) => void
  onClose: () => void
}

export default function InstallDialog({
  planInfo,
  app,
  open,
  onClose,
  selectedAccount,
  setSelectedAccount,
}: InstallDialogProps) {
  const [selectedPlanId, setSelectedPlanId] = useState(planInfo.selectedPlanId)

  const onPlanChange = (planId: string) => {
    setSelectedPlanId(planId)
  }

  const selectedPlan = useMemo(() => {
    return planInfo.plans.find(plan => plan.id === selectedPlanId)
  }, [planInfo.plans, selectedPlanId])

  const numPlans = planInfo.plans.length

  if (!open || !selectedPlan) {
    return null
  }

  return (
    <Dialog
      title="Configure your installation"
      onClose={onClose}
      renderFooter={() => (
        <Dialog.Footer>
          <InstallButton planInfo={planInfo} plan={selectedPlan} listing={app} account={selectedAccount} />
        </Dialog.Footer>
      )}
      position={{
        narrow: numPlans > 5 ? 'fullscreen' : 'bottom',
        regular: 'center',
      }}
    >
      {numPlans > 1 && (
        <PlansRadioGroup planInfo={planInfo} onPlanChange={onPlanChange} selectedPlanId={selectedPlanId} />
      )}
      <PlanForm
        planInfo={planInfo}
        listing={app}
        plan={selectedPlan}
        selectedAccount={selectedAccount}
        onAccountSelect={setSelectedAccount}
      >
        <Stack gap="normal" className={selectedPlan.isPaid && !selectedPlan.perUnit ? '' : 'pt-3'}>
          <PlanFormSeatsField />
          <PlanFormAccountSelector />
        </Stack>
      </PlanForm>
    </Dialog>
  )
}
