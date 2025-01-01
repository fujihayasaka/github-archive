import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {sendEvent} from '@github-ui/hydro-analytics'
import {LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'

import styles from './FreeChatExceededBanner.module.css'

export function FreeChatExceededBanner() {
  const {resetDate} = useEntitlement()

  const description = `You have reached your free plan limit. Limit resets on ${resetDate}.`

  const primaryAction = (
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
  )

  return (
    <div className={styles.container}>
      <Banner
        variant="upsell"
        title="Limit reached"
        description={description}
        hideTitle
        primaryAction={primaryAction}
      />
    </div>
  )
}
