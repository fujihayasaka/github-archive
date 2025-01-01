import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {
  ENABLE_ADDITIONAL_REQUESTS_URL,
  MANAGE_BILLING_URL,
  PREMIUM_QUOTA_TRIGGER,
  UPGRADE_PLAN_URL,
} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {sendEvent} from '@github-ui/hydro-analytics'
import {Link, LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useEffect, useState} from 'react'

const triggerValue = copilotFeatureFlags.premiumRequestQuotasEnabled ? PREMIUM_QUOTA_TRIGGER : 10

export function useQuotaMeterBannerVisibility() {
  const {
    isLicensedLimited,
    chatQuotaRemaining,
    premiumChatQuotaRemaining,
    premiumInteractionsQuotaExceeded,
    overagesEnabled,
  } = useEntitlement()
  const [isVisible, setIsVisible] = useState<boolean>(() => {
    return copilotLocalStorage.getMeterBannerFlag() ?? false
  })

  useEffect(() => {
    if ((isLicensedLimited || copilotFeatureFlags.premiumRequestQuotasEnabled) && chatQuotaRemaining !== undefined) {
      const existingFlag = copilotLocalStorage.getMeterBannerFlag()

      if (
        (chatQuotaRemaining > 0 && chatQuotaRemaining <= triggerValue) ||
        (!isLicensedLimited && premiumChatQuotaRemaining > 0 && premiumChatQuotaRemaining <= triggerValue) ||
        (!isLicensedLimited && premiumInteractionsQuotaExceeded && overagesEnabled)
      ) {
        if (existingFlag === null) {
          copilotLocalStorage.setMeterBannerFlag(true)
          setIsVisible(true)
        } else {
          setIsVisible(existingFlag)
        }
      } else {
        copilotLocalStorage.removeMeterBannerFlag()
        setIsVisible(false)
      }
    }
  }, [
    isLicensedLimited,
    chatQuotaRemaining,
    premiumChatQuotaRemaining,
    overagesEnabled,
    premiumInteractionsQuotaExceeded,
  ])

  const handleDismiss = () => {
    copilotLocalStorage.setMeterBannerFlag(false)
    setIsVisible(false)
  }

  return {
    visible:
      isVisible &&
      chatQuotaRemaining !== undefined &&
      (isLicensedLimited || copilotFeatureFlags.premiumRequestQuotasEnabled),
    onDismiss: handleDismiss,
  }
}

interface QuotaMeterBannerProps {
  onDismiss: () => void
  className?: string
}

export function QuotaMeterBanner({onDismiss, className}: QuotaMeterBannerProps) {
  const {isLicensedLimited, canUpgradePlan, canPurchaseAdditionalQuota, premiumInteractionsQuotaExceeded, resetDate} =
    useEntitlement()

  const description = isLicensedLimited
    ? `You have used ${100 - triggerValue}% of your free requests this month.`
    : !premiumInteractionsQuotaExceeded
      ? `You have used ${100 - triggerValue}% of your premium responses this month. ${
          canUpgradePlan
            ? 'Upgrade to increase your limit.'
            : 'Enable additional requests to get more usage after the limit is reached.'
        }`
      : `You have used all premium requests available this month. You will be charged per additional premium request until the limit resets on ${resetDate}.`

  const primaryAction =
    canUpgradePlan && !premiumInteractionsQuotaExceeded ? (
      <LinkButton
        as="a"
        href={UPGRADE_PLAN_URL}
        onClick={() => {
          sendEvent('dotcom_chat.activate', {
            target: 'QUOTA_METER_BANNER_LINK_UPGRADE',
            mode: 'immersive',
          })
        }}
      >
        Upgrade
      </LinkButton>
    ) : canPurchaseAdditionalQuota && !premiumInteractionsQuotaExceeded ? (
      <LinkButton
        as="a"
        href={ENABLE_ADDITIONAL_REQUESTS_URL}
        onClick={() => {
          sendEvent('dotcom_chat.activate', {
            target: 'QUOTA_METER_BANNER_LINK_OVERAGES',
            mode: 'immersive',
          })
        }}
      >
        Enable additional requests
      </LinkButton>
    ) : (
      <LinkButton
        as="a"
        href={MANAGE_BILLING_URL}
        onClick={() => {
          sendEvent('dotcom_chat.activate', {
            target: 'QUOTA_METER_BANNER_LINK_MANAGE_BILLING',
            mode: 'immersive',
          })
        }}
      >
        Manage billing
      </LinkButton>
    )

  const secondaryAction =
    canUpgradePlan && canPurchaseAdditionalQuota && !premiumInteractionsQuotaExceeded ? (
      <Link
        as="a"
        href={UPGRADE_PLAN_URL}
        onClick={() => {
          sendEvent('dotcom_chat.activate', {
            target: 'QUOTA_METER_BANNER_LINK_UPGRADE',
            mode: 'immersive',
          })
        }}
      >
        Enable additional requests
      </Link>
    ) : null

  return (
    <div className={className}>
      <Banner
        variant="info"
        title="Limit reached soon"
        description={description}
        hideTitle
        primaryAction={primaryAction}
        secondaryAction={secondaryAction}
        onDismiss={() => {
          onDismiss()
          sendEvent('dotcom_chat.activate', {
            target: 'QUOTA_METER_BANNER_DISMISS',
            mode: 'immersive',
          })
        }}
      />
    </div>
  )
}
