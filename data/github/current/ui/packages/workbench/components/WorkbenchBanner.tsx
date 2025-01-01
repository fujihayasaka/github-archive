import {CopilotLicenseType, CopilotPlan} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import {Link, LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useCallback, useEffect, useState} from 'react'

import {useWorkbenchStore} from '../contexts/WorkbenchStoreContext'
import {getChatQuotaApproaching, removeChatQuotaApproaching, setChatQuotaApproaching} from '../utilities/copilot-chat'
import {EntitledService, initialState} from '../utilities/workbench-store-reducer'

const ActionLabel = {
  EnableAdditionalRequests: 'Enable additional requests',
  ManageBilling: 'Manage billing',
  Upgrade: 'Upgrade',
} as const

type ActionLabelType = (typeof ActionLabel)[keyof typeof ActionLabel]

const ActionUrl: Record<ActionLabelType, string> = {
  [ActionLabel.EnableAdditionalRequests]: 'https://github.com/settings/billing/budgets/new',
  [ActionLabel.ManageBilling]: 'https://github.com/settings/billing/budgets/new',
  [ActionLabel.Upgrade]: 'https://github.com/features/copilot/plans?cft=copilot_li.features_copilot',
}

interface BannerAction {
  label: ActionLabelType
  url: string
}

const PREMIUM_REQUESTS_LINK =
  'https://docs.github.com/en/copilot/managing-copilot/monitoring-usage-and-entitlements/about-premium-requests'

const PremiumRequestsLink = () => {
  return (
    <Link inline href={PREMIUM_REQUESTS_LINK}>
      premium requests
    </Link>
  )
}

const ResetDateMessage = ({resetDate}: {resetDate: string}) => {
  return resetDate ? <> Limit resets on {formatDate(resetDate)}.</> : null
}

const renderActionButton = (action: BannerAction | null | undefined, variant?: 'invisible') => {
  if (!action) return undefined

  const eventTarget = `COPILOT_WORKBENCH_BANNER_LINK_${action.label.split(' ').join('_').toUpperCase()}`

  return (
    <LinkButton
      as="a"
      href={action.url}
      onClick={() => {
        sendEvent('dotcom_chat.activate', {target: eventTarget, action: 'click'})
      }}
      variant={variant}
    >
      {action.label}
    </LinkButton>
  )
}

export function WorkbenchBanner() {
  const [isBannerVisible, setIsBannerVisible] = useState<boolean>(() => getChatQuotaApproaching() ?? false)
  const {entitlement} = useWorkbenchStore()
  const copilot = entitlement[EntitledService.COPILOT] ?? initialState.entitlement[EntitledService.COPILOT]
  const {plan, licenseType, quotas = initialState.entitlement[EntitledService.COPILOT].quotas} = copilot
  const {remaining, resetDate, overagesEnabled} = quotas
  const adminStatus = entitlement[EntitledService.USER_STATUS]?.admin ?? false
  const billingUrl = entitlement[EntitledService.USER_STATUS]?.billingUrl
  const ownerType =
    entitlement[EntitledService.USER_STATUS]?.type ?? initialState.entitlement[EntitledService.USER_STATUS].type

  const isLicensedLimited = licenseType === CopilotLicenseType.LicensedLimited
  const isPaidPlan =
    plan === CopilotPlan.IndividualPro ||
    plan === CopilotPlan.IndividualProPlus ||
    plan === CopilotPlan.Business ||
    plan === CopilotPlan.Enterprise
  const premiumInteractionsQuotaExceeded = (remaining.premiumInteractions ?? 0) <= 0
  const chatQuotaExceeded = remaining.chat <= 0
  const premiumChatQuotaRemaining = remaining.premiumInteractionsPercentage ?? 0
  const chatQuotaRemaining = remaining.chatPercentage ?? 0
  const canUpgradePlan = isLicensedLimited || plan === CopilotPlan.IndividualPro || plan === CopilotPlan.Business
  const canPurchaseAdditionalQuota = !isLicensedLimited && isPaidPlan

  const chatQuotaApproaching = chatQuotaRemaining <= 50 && chatQuotaRemaining > 0
  const premiumInteractionsQuotaApproaching = premiumChatQuotaRemaining <= 20 && premiumChatQuotaRemaining > 0
  const isQuotaApproaching =
    (isLicensedLimited && chatQuotaApproaching) || (isPaidPlan && premiumInteractionsQuotaApproaching)
  const isQuotaExceeded = (isLicensedLimited && chatQuotaExceeded) || (isPaidPlan && premiumInteractionsQuotaExceeded)

  const variant = getVariant(isQuotaExceeded, overagesEnabled)
  const dismissible = getDismissible(isQuotaApproaching, isQuotaExceeded, overagesEnabled)

  const primaryAction = getPrimaryAction(
    canPurchaseAdditionalQuota,
    canUpgradePlan,
    overagesEnabled,
    premiumInteractionsQuotaExceeded,
    ownerType as string | undefined,
    adminStatus,
    billingUrl,
  )

  const secondaryAction = getSecondaryAction(
    canPurchaseAdditionalQuota,
    overagesEnabled,
    plan,
    premiumInteractionsQuotaExceeded,
    ownerType as string | undefined,
    adminStatus,
    billingUrl,
  )

  const description = getDescription(
    isQuotaApproaching,
    isQuotaExceeded,
    overagesEnabled,
    plan,
    premiumInteractionsQuotaApproaching,
    premiumInteractionsQuotaExceeded,
    resetDate,
    adminStatus,
  )

  useEffect(() => {
    const flag = getChatQuotaApproaching()
    if (isQuotaApproaching) {
      if (flag === null) {
        setChatQuotaApproaching(true)
        setIsBannerVisible(true)
      } else {
        setIsBannerVisible(flag)
      }
    } else {
      removeChatQuotaApproaching()
      setIsBannerVisible(true)
    }
  }, [isQuotaApproaching])

  const handleDismiss = useCallback(() => {
    setChatQuotaApproaching(false)
    setIsBannerVisible(false)
  }, [])

  return copilotFeatureFlags.workbenchUserLimits && isBannerVisible && description ? (
    <Banner
      className="mx-3 mb-2"
      hideTitle
      title={primaryAction?.label || 'Copilot status'}
      variant={variant}
      onDismiss={dismissible ? handleDismiss : undefined}
      primaryAction={renderActionButton(primaryAction)}
      secondaryAction={renderActionButton(secondaryAction, 'invisible')}
      description={description}
    />
  ) : null
}

function getVariant(isQuotaExceeded: boolean, overagesEnabled: boolean) {
  if (isQuotaExceeded && overagesEnabled) {
    return 'info'
  }

  if (isQuotaExceeded && !overagesEnabled) {
    return 'upsell'
  }

  return 'info'
}

function getDismissible(isQuotaApproaching: boolean, isQuotaExceeded: boolean, overagesEnabled: boolean) {
  if (isQuotaApproaching || (isQuotaExceeded && overagesEnabled)) {
    return true
  }

  return false
}

function isAdmin(ownerType: string | undefined, adminStatus: boolean) {
  return ownerType === 'Organization' ? adminStatus : false
}

function getPrimaryAction(
  canPurchaseAdditionalQuota: boolean,
  canUpgradePlan: boolean,
  overagesEnabled: boolean,
  premiumInteractionsQuotaExceeded: boolean,
  ownerType: string | undefined,
  adminStatus: boolean,
  billingUrl?: string,
): BannerAction | null {
  let label: ActionLabelType | null = null

  if (canUpgradePlan && !overagesEnabled) {
    label = ActionLabel.Upgrade
  } else if (overagesEnabled && premiumInteractionsQuotaExceeded) {
    label = ActionLabel.ManageBilling
  } else if (canPurchaseAdditionalQuota) {
    label = ActionLabel.EnableAdditionalRequests
  } else {
    label = ActionLabel.Upgrade
  }

  if (!label) return null
  const admin = isAdmin(ownerType, adminStatus)
  if (ownerType === 'Organization' && admin) {
    return {label, url: billingUrl!}
  } else if (ownerType === 'Organization' && !admin) {
    return null
  }
  return {label, url: ActionUrl[label]}
}

function getSecondaryAction(
  canPurchaseAdditionalQuota: boolean,
  overagesEnabled: boolean,
  plan: CopilotPlan,
  premiumInteractionsQuotaExceeded: boolean,
  ownerType: string | undefined,
  adminStatus: boolean,
  billingUrl?: string,
): BannerAction | null {
  let label: ActionLabelType | null = null

  if (
    (plan === CopilotPlan.IndividualPro && premiumInteractionsQuotaExceeded && !overagesEnabled) ||
    (plan === CopilotPlan.Business && canPurchaseAdditionalQuota)
  ) {
    label = ActionLabel.EnableAdditionalRequests
  }

  if (!label) return null
  const admin = isAdmin(ownerType, adminStatus)
  if (ownerType === 'Organization' && admin) {
    return {label, url: billingUrl!}
  } else if (ownerType === 'Organization' && !admin) {
    return null
  }
  return {label, url: ActionUrl[label]}
}

function getDescription(
  isQuotaApproaching: boolean,
  isQuotaExceeded: boolean,
  overagesEnabled: boolean,
  plan: CopilotPlan,
  premiumInteractionsQuotaApproaching: boolean,
  premiumInteractionsQuotaExceeded: boolean,
  resetDate: string,
  adminStatus: boolean,
): React.ReactNode | undefined {
  switch (plan) {
    case CopilotPlan.IndividualFree:
      if (isQuotaApproaching) {
        return (
          <>
            You have used 50% of your <PremiumRequestsLink /> this month.
          </>
        )
      }

      if (isQuotaExceeded) {
        return (
          <>
            You have reached your free plan limit. Upgrade to continue editing sparks.{' '}
            <ResetDateMessage resetDate={resetDate} />
          </>
        )
      }
      break
    case CopilotPlan.IndividualPro:
      if (premiumInteractionsQuotaApproaching && !overagesEnabled) {
        return (
          <>
            You have used 80% of your <PremiumRequestsLink /> this month. Upgrade to increase your limit for editing
            sparks.
          </>
        )
      }

      if (premiumInteractionsQuotaExceeded && !overagesEnabled) {
        return (
          <>
            You have reached your monthly limit for <PremiumRequestsLink />. Select an upgrade option to continue
            editing sparks. <ResetDateMessage resetDate={resetDate} />
          </>
        )
      }

      if (premiumInteractionsQuotaExceeded && overagesEnabled) {
        return (
          <>
            You have used all <PremiumRequestsLink /> available this month. You will be charged per additional prompt
            <span>{resetDate !== '' ? ` until the limit resets on ${resetDate}` : null}</span>.
          </>
        )
      }
      break
    case CopilotPlan.IndividualProPlus:
      if (premiumInteractionsQuotaApproaching && !overagesEnabled) {
        return (
          <>
            You have used 80% of your <PremiumRequestsLink /> this month. Enable additional requests to increase your
            limit for editing sparks.
          </>
        )
      }

      if (premiumInteractionsQuotaExceeded && !overagesEnabled) {
        return (
          <>
            You have reached your monthly limit for <PremiumRequestsLink />. Enable additional requests to increase your
            limit for editing sparks. <ResetDateMessage resetDate={resetDate} />
          </>
        )
      }

      if (premiumInteractionsQuotaExceeded && overagesEnabled) {
        return (
          <>
            You have used all <PremiumRequestsLink /> available this month. You will be charged per additional prompt
            <span>{resetDate !== '' ? ` until the limit resets on ${resetDate}` : null}</span>.
          </>
        )
      }
      break
    case CopilotPlan.Business:
      if (adminStatus) {
        if (premiumInteractionsQuotaApproaching && !overagesEnabled) {
          return (
            <>
              You have used 80% of your <PremiumRequestsLink /> this month. Select an upgrade option to increase your
              limit for editing Sparks.
            </>
          )
        }

        if (premiumInteractionsQuotaExceeded && !overagesEnabled) {
          return (
            <>
              You have reached your monthly limit for <PremiumRequestsLink />. Select an upgrade option to continue
              editing Sparks. <ResetDateMessage resetDate={resetDate} />
            </>
          )
        }
      } else {
        if (premiumInteractionsQuotaApproaching && !overagesEnabled) {
          return (
            <>
              You have used 80% of your <PremiumRequestsLink /> this month. Ask your admin to{' '}
              <b>enable additional requests</b> to increase your limit for editing Sparks.
            </>
          )
        }

        if (premiumInteractionsQuotaExceeded && !overagesEnabled) {
          return (
            <>
              You have reached your monthly limit for <PremiumRequestsLink />. Ask your admin to{' '}
              <b>upgrade to Copilot Enterprise</b> to continue editing Sparks.{' '}
              <ResetDateMessage resetDate={resetDate} />
            </>
          )
        }
      }

      if (premiumInteractionsQuotaExceeded && overagesEnabled) {
        return undefined
      }
      break
    case CopilotPlan.Enterprise:
      if (adminStatus) {
        if (premiumInteractionsQuotaApproaching && !overagesEnabled) {
          return (
            <>
              You have used 80% of your <PremiumRequestsLink /> this month. Enable additional requests to increase your
              limit for editing Sparks.
            </>
          )
        }

        if (premiumInteractionsQuotaExceeded && !overagesEnabled) {
          return (
            <>
              You have reached your monthly limit for <PremiumRequestsLink />. Enable additional requests to continue
              editing Sparks. <ResetDateMessage resetDate={resetDate} />
            </>
          )
        }
      } else {
        if (premiumInteractionsQuotaApproaching && !overagesEnabled) {
          return (
            <>
              You have used 80% of your <PremiumRequestsLink /> this month. Ask your admin to{' '}
              <b>enable additional requests</b> to increase your limit for editing Sparks.
            </>
          )
        }

        if (premiumInteractionsQuotaExceeded && !overagesEnabled) {
          return (
            <>
              You have reached your monthly limit for <PremiumRequestsLink />. Ask your admin to{' '}
              <b>enable additional requests</b> to continue editing Sparks. <ResetDateMessage resetDate={resetDate} />
            </>
          )
        }
      }

      if (premiumInteractionsQuotaExceeded && overagesEnabled) {
        return undefined
      }
      break
  }
  return undefined
}

function formatDate(date: string) {
  // Add time (noon UTC) to ensure the date is interpreted correctly across time zones
  return new Date(`${date}T12:00:00Z`).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}
