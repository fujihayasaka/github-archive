import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {sendEvent} from '@github-ui/hydro-analytics'
import {Link, LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useEffect, useState} from 'react'

import styles from './QuotaExceededBanner.module.css'

export function useQuotaExceededBannerVisibility() {
  const {
    isLicensedLimited,
    chatQuotaRemaining,
    premiumChatQuotaRemaining,
    premiumInteractionsQuotaExceeded,
    overagesEnabled,
  } = useEntitlement()
  const [isVisible, setIsVisible] = useState<boolean>(() => {
    return copilotLocalStorage.getQuotaExceededBannerFlag() ?? false
  })

  useEffect(() => {
    if (copilotFeatureFlags.premiumRequestQuotasEnabled && chatQuotaRemaining !== undefined) {
      const existingFlag = copilotLocalStorage.getQuotaExceededBannerFlag()

      if (copilotFeatureFlags.premiumRequestQuotasEnabled && !overagesEnabled && premiumInteractionsQuotaExceeded) {
        if (existingFlag === null) {
          // always show for licensed limited users
          copilotLocalStorage.setQuotaExceededBannerFlag(true)
          setIsVisible(true)
        } else {
          setIsVisible(existingFlag)
        }
      } else {
        copilotLocalStorage.removeQuotaExceededBannerFlag()
        setIsVisible(false)
      }
    }
  }, [chatQuotaRemaining, premiumChatQuotaRemaining, overagesEnabled, premiumInteractionsQuotaExceeded])

  const handleDismiss = () => {
    copilotLocalStorage.setQuotaExceededBannerFlag(false)
    setIsVisible(false)
  }

  return {
    visible:
      isVisible &&
      !isLicensedLimited &&
      chatQuotaRemaining !== undefined &&
      copilotFeatureFlags.premiumRequestQuotasEnabled,
    onDismiss: handleDismiss,
  }
}

interface QuotaExceededBannerProps {
  onDismiss: () => void
}

export function QuotaExceededBanner({onDismiss}: QuotaExceededBannerProps) {
  const {canUpgradePlan, canPurchaseAdditionalQuota, resetDate} = useEntitlement()

  const description = `You have reached your monthly limit for premium requests. ${
    canUpgradePlan
      ? `Select an upgrade option or switch to the default model. Limit resets on ${resetDate}.`
      : `Enable additional requests or switch to the default model. Limit resets on ${resetDate}.`
  }`

  const primaryAction = canUpgradePlan ? (
    <LinkButton
      as="a"
      href="https://github.com/features/copilot#pricing"
      onClick={() => {
        sendEvent('dotcom_chat.activate', {
          target: 'QUOTA_METER_BANNER_LINK_UPGRADE',
          mode: 'immersive',
        })
      }}
    >
      Upgrade
    </LinkButton>
  ) : canPurchaseAdditionalQuota ? (
    <LinkButton
      as="a"
      href="https://github.com/features/copilot#pricing"
      onClick={() => {
        sendEvent('dotcom_chat.activate', {
          target: 'QUOTA_METER_BANNER_LINK_UPGRADE',
          mode: 'immersive',
        })
      }}
    >
      Enable additional requests
    </LinkButton>
  ) : null

  const secondaryAction =
    canUpgradePlan && canPurchaseAdditionalQuota ? (
      <Link
        as="a"
        href="https://github.com/features/copilot#pricing"
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
    <div className={styles.container}>
      <Banner
        variant="upsell"
        title="Limit reached"
        description={description}
        hideTitle
        primaryAction={primaryAction}
        secondaryAction={secondaryAction}
        onDismiss={() => {
          onDismiss()
          sendEvent('dotcom_chat.activate', {
            target: 'QUOTA_EXCEEDED_BANNER_DISMISS',
            mode: 'immersive',
          })
        }}
      />
    </div>
  )
}
