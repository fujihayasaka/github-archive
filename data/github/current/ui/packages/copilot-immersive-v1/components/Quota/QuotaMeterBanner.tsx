import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {sendEvent} from '@github-ui/hydro-analytics'
import {LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useEffect, useState} from 'react'

const triggerValue = 10

export function useQuotaMeterBannerVisibility() {
  const {isLicensedLimited, chatQuotaRemaining} = useEntitlement()
  const [isVisible, setIsVisible] = useState<boolean>(() => {
    return copilotLocalStorage.getMeterBannerFlag() ?? false
  })

  useEffect(() => {
    if (isLicensedLimited && chatQuotaRemaining !== undefined) {
      const existingFlag = copilotLocalStorage.getMeterBannerFlag()

      if (chatQuotaRemaining > 0 && chatQuotaRemaining <= triggerValue) {
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
  }, [isLicensedLimited, chatQuotaRemaining])

  const handleDismiss = () => {
    copilotLocalStorage.setMeterBannerFlag(false)
    setIsVisible(false)
  }

  return {
    visible: isVisible && chatQuotaRemaining !== undefined && isLicensedLimited,
    onDismiss: handleDismiss,
  }
}

interface QuotaMeterBannerProps {
  onDismiss: () => void
  className?: string
}

export function QuotaMeterBanner({onDismiss, className}: QuotaMeterBannerProps) {
  const {resetDate} = useEntitlement()

  return (
    <div className={className}>
      <Banner
        variant="upsell"
        title="Limit reached soon"
        description={`You only have a few free responses remaining. Your limit resets on ${resetDate}.`}
        hideTitle
        primaryAction={
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
        }
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
