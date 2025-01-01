import {sendEvent} from '@github-ui/hydro-analytics'
import {InfoIcon} from '@primer/octicons-react'
import {LinkButton} from '@primer/react'
import {useEffect, useState} from 'react'

import {useEntitlement} from '../../components/quota/EntitlementContext'
import {copilotLocalStorage} from '../../utils/copilot-local-storage'
import {CustomBanner} from './CustomBanner'
import styles from './QuotaMeterBanner.module.css'

export function QuotaMeterBanner() {
  const {isLicensedLimited, chatQuotaRemaining} = useEntitlement()
  const [isVisible, setIsVisible] = useState<boolean>(() => {
    return copilotLocalStorage.getMeterBannerFlag() ?? false
  })
  const triggerValue = 10

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

  if (!isVisible || chatQuotaRemaining === undefined) {
    return null
  }

  const icon = <InfoIcon />
  const content = <>You only have a few free responses remaining.</>
  const actions = (
    <LinkButton
      as="a"
      href="https://github.com/features/copilot#pricing"
      onClick={() => {
        sendEvent('dotcom_chat.activate', {
          target: 'QUOTA_METER_BANNER_LINK_UPGRADE',
          mode: 'assistive',
        })
      }}
    >
      Upgrade
    </LinkButton>
  )

  return (
    <div className={styles.container}>
      <CustomBanner icon={icon} content={content} actions={actions} onDismiss={handleDismiss} />
    </div>
  )
}
