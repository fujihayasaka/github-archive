import type {PlanInfo} from '../../types'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import type {AppListing} from '@github-ui/marketplace-common'
import {PlanForm} from './pricing-plans/PlanForm'
import InstallDialog from './InstallDialog'
import {useState} from 'react'
import {HeaderButton, HeaderLinkButton} from './HeaderButton'
import {HeaderInstallButton} from './pricing-plans/InstallButton'
import PlanFormAccountSelector from './pricing-plans/form/PlanFormAccountSelector'

interface SetupButtonProps {
  planInfo: PlanInfo
  app: AppListing
}

interface DialogButtonProps extends SetupButtonProps {
  selectedAccount?: string
  setSelectedAccount: (account: string) => void
}

export function callToActionText(planInfo: PlanInfo) {
  return planInfo.viewerHasPurchased || planInfo.anyOrgsPurchased
    ? 'Add'
    : planInfo.plans.some(plan => plan.hasFreeTrial)
      ? 'Set up a free trial'
      : 'Add'
}

function DialogButton({planInfo, app, selectedAccount, setSelectedAccount}: DialogButtonProps) {
  const [showDialog, setShowDialog] = useState(false)
  return (
    <>
      <HeaderButton planInfo={planInfo} data-testid="dialog-button" onClick={() => setShowDialog(true)}>
        {callToActionText(planInfo)}
      </HeaderButton>
      <InstallDialog
        planInfo={planInfo}
        app={app}
        open={showDialog}
        selectedAccount={selectedAccount}
        setSelectedAccount={setSelectedAccount}
        onClose={() => setShowDialog(false)}
      />
    </>
  )
}

export function CallToAction(props: SetupButtonProps) {
  const {planInfo, app} = props
  const canReinstall = useFeatureFlag('marketplace_purchase_reconciliation') && !planInfo.installedForViewer
  const hideButton = planInfo.viewerHasPurchased && planInfo.viewerHasPurchasedForAllOrganizations && !canReinstall
  const marketplaceFreeInstallFlag = useFeatureFlag('marketplace_free_install')
  const [selectedAccount, setSelectedAccount] = useState(planInfo.selectedAccount || planInfo.currentUser?.displayLogin)

  if (hideButton) {
    return null
  }

  if (!marketplaceFreeInstallFlag || !app.copilotApp) {
    return (
      <HeaderLinkButton
        planInfo={planInfo}
        href="#pricing-and-setup"
        className="js-smoothscroll-anchor"
        data-testid="setup-button"
      >
        {callToActionText(planInfo)}
      </HeaderLinkButton>
    )
  }

  const hasMultipleAccounts = planInfo.organizations.length > 0
  const hasMultiplePlans = planInfo.plans.length > 1
  const selectedPlan = planInfo.plans.find(plan => plan.id === planInfo.selectedPlanId)!
  const hasPaidPlan = selectedPlan.isPaid

  if (hasMultipleAccounts || hasMultiplePlans || hasPaidPlan)
    return (
      <DialogButton
        planInfo={planInfo}
        app={app}
        selectedAccount={selectedAccount}
        setSelectedAccount={setSelectedAccount}
      />
    )

  // if there is only one free plan and one account, link directly to the install page
  return (
    <PlanForm
      planInfo={planInfo}
      listing={app}
      plan={selectedPlan}
      selectedAccount={selectedAccount}
      onAccountSelect={setSelectedAccount}
    >
      <PlanFormAccountSelector />
      <HeaderInstallButton planInfo={planInfo} plan={selectedPlan} listing={app} account={selectedAccount} />
    </PlanForm>
  )
}
