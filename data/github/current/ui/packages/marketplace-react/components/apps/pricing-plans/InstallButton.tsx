import {useMemo} from 'react'
import type {PlanInfo, Plan} from '../../../types'
import type {AppListing} from '@github-ui/marketplace-common'
import {Button} from '@primer/react'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {HeaderButton, HeaderLinkButton} from '../HeaderButton'
import {loginPath} from '@github-ui/paths'
import {useClientValue} from '@github-ui/use-client-value'
import {ssrSafeLocation} from '@github-ui/ssr-utils'

type Props = {
  planInfo: PlanInfo
  plan: Plan
  listing: AppListing
  account?: string
}

export function installButtonAttributes(
  planInfo: PlanInfo,
  plan: Plan,
  listing: AppListing,
  selectedAccount?: string,
  marketplacePurchaseReconciliationFlag?: boolean,
) {
  let isDisabled
  let buttonText

  const installedForSelectedAccount = (() => {
    if (!selectedAccount) return false
    if (selectedAccount === planInfo.currentUser?.displayLogin) {
      return planInfo.installedForViewer
    } else {
      return planInfo.organizations.find(org => org.displayLogin === selectedAccount)?.installedForOrg
    }
  })()

  const purchasedForAccount =
    marketplacePurchaseReconciliationFlag && selectedAccount && planInfo.planIdByLogin[selectedAccount] === plan.id
  const purchasedAndInstalledForAccount = purchasedForAccount && installedForSelectedAccount
  const purchasedButNotInstalled = purchasedForAccount && !installedForSelectedAccount

  if (purchasedAndInstalledForAccount) {
    isDisabled = true
    buttonText = 'Already installed'
  } else if (purchasedButNotInstalled) {
    isDisabled = false
    buttonText = 'Install'
  } else if (plan.directBilling) {
    isDisabled = !planInfo.isBuyable
    buttonText = `Set up with ${listing.name}`
  } else if (
    plan.isPaid &&
    plan.hasFreeTrial &&
    (planInfo.subscriptionItem.onFreeTrial || planInfo.anyAccountEligibleForFreeTrial)
  ) {
    isDisabled = !planInfo.isBuyable
    if (planInfo.isBuyable || planInfo.organizations.length > 0) {
      buttonText = `Try free for ${planInfo.freeTrialLength}`
    } else if (planInfo.viewerFreeTrialDaysLeft && planInfo.viewerFreeTrialDaysLeft > 0) {
      buttonText = `${planInfo.viewerFreeTrialDaysLeft} ${
        planInfo.viewerFreeTrialDaysLeft === 1 ? 'day' : 'days'
      } left of free trial`
    } else {
      buttonText = `Try free for ${planInfo.freeTrialLength}`
    }
  } else if (plan.isPaid) {
    isDisabled = !planInfo.isBuyable
    buttonText = 'Buy with GitHub'
  } else if (planInfo.isBuyable) {
    isDisabled = false
    buttonText = 'Install it for free'
  } else {
    isDisabled = true
    buttonText = 'Install it for free'
  }

  return {
    isDisabled,
    buttonText,
  }
}

export function HeaderInstallButton({planInfo, plan, listing, account}: Props) {
  const marketplacePurchaseReconciliationFlag = useFeatureFlag('marketplace_purchase_reconciliation')
  const {isDisabled, buttonText} = useMemo(() => {
    return installButtonAttributes(planInfo, plan, listing, account, marketplacePurchaseReconciliationFlag)
  }, [planInfo, plan, listing, account, marketplacePurchaseReconciliationFlag])

  const [loginUrl] = useClientValue(
    () => {
      return loginPath({
        returnTo: ssrSafeLocation?.href,
      })
    },
    undefined,
    [ssrSafeLocation?.href],
  )

  if (!planInfo.isLoggedIn) {
    return (
      <HeaderLinkButton href={loginUrl} planInfo={planInfo} disabled={isDisabled}>
        {buttonText}
      </HeaderLinkButton>
    )
  }

  return (
    <HeaderButton
      type="submit"
      form="plan-form"
      planInfo={planInfo}
      disabled={isDisabled}
      data-testid="direct-install-button"
      data-octo-click="marketplace-listing_order_click"
      data-octo-dimensions={`marketplace_listing_id:${listing.id}`}
    >
      {buttonText}
    </HeaderButton>
  )
}

export function InstallButton({planInfo, plan, listing, account}: Props) {
  const marketplacePurchaseReconciliationFlag = useFeatureFlag('marketplace_purchase_reconciliation')
  const {isDisabled, buttonText} = useMemo(() => {
    return installButtonAttributes(planInfo, plan, listing, account, marketplacePurchaseReconciliationFlag)
  }, [planInfo, plan, listing, account, marketplacePurchaseReconciliationFlag])

  return (
    <Button
      variant="primary"
      size="large"
      form="plan-form"
      disabled={isDisabled}
      type="submit"
      data-octo-click="marketplace-listing_order_click"
      data-octo-dimensions={`marketplace_listing_id:${listing.id}`}
    >
      {buttonText}
    </Button>
  )
}
