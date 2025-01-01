import {useMemo} from 'react'
import type {PlanInfo, Plan} from '../../../types'
import type {AppListing} from '@github-ui/marketplace-common'
import {Stack} from '@primer/react'
import {InstallButton} from './InstallButton'
import {InstallHelpText} from './InstallHelpText'
import PlanFormProvider from './form/PlanFormContext'
import PlanFormHiddenFields from './form/PlanFormHiddenFields'
import PlanFormSeatsField from './form/PlanFormSeatsField'
import PlanFormAccountSelector from './form/PlanFormAccountSelector'

type PlanFormProps = {
  planInfo: PlanInfo
  listing: AppListing
  plan: Plan
  selectedAccount?: string
  onAccountSelect: (account: string) => void
  children?: React.ReactNode
}

export function PlanForm({planInfo, listing, plan, children, selectedAccount, onAccountSelect}: PlanFormProps) {
  const skipOrderReview = useMemo(() => {
    // For Copilot Extensions, we skip the order review stage since they're free
    if (listing.copilotApp && !plan.isPaid) {
      return true
    }

    // For direct billing plans, we skip the order review stage since payment is setup outside of GitHub
    return plan.directBilling
  }, [listing.copilotApp, plan.directBilling, plan.isPaid])

  const installedForSelectedAccount = useMemo(() => {
    if (!selectedAccount) return false
    if (selectedAccount === planInfo.currentUser?.displayLogin) {
      return planInfo.installedForViewer
    } else {
      return planInfo.organizations.find(org => org.displayLogin === selectedAccount)?.installedForOrg
    }
  }, [planInfo.organizations, selectedAccount, planInfo.installedForViewer, planInfo.currentUser?.displayLogin])

  const purchasedForAccount = !!selectedAccount && planInfo.planIdByLogin[selectedAccount] === plan.id
  const purchasedButNotInstalled = purchasedForAccount && !installedForSelectedAccount
  const alreadyPurchased = skipOrderReview && selectedAccount && planInfo.planIdByLogin[selectedAccount]

  return (
    <PlanFormProvider
      planInfo={planInfo}
      listing={listing}
      plan={plan}
      selectedAccount={selectedAccount}
      setSelectedAccount={onAccountSelect}
      canReinstall={purchasedButNotInstalled}
      skipOrderReview={skipOrderReview}
    >
      <form
        method={skipOrderReview || purchasedButNotInstalled ? 'POST' : 'GET'}
        action={`/marketplace/${listing.slug}/order/${plan.id}${
          alreadyPurchased || purchasedButNotInstalled ? '/upgrade' : ''
        }`}
        data-testid="plan-form"
        className="width-full"
        id="plan-form"
      >
        <PlanFormHiddenFields />
        {children ? (
          children
        ) : (
          <Stack gap="normal" className={plan.isPaid && !plan.perUnit ? '' : 'pt-3'}>
            <PlanFormSeatsField />
            <PlanFormAccountSelector />
            <div>
              <InstallButton planInfo={planInfo} plan={plan} listing={listing} account={selectedAccount} />
              <InstallHelpText planInfo={planInfo} plan={plan} listing={listing} />
            </div>
          </Stack>
        )}
      </form>
    </PlanFormProvider>
  )
}
