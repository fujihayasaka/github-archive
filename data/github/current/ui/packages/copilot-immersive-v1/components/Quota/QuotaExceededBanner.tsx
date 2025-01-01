import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {sendEvent} from '@github-ui/hydro-analytics'
import {LinkButton} from '@primer/react'
import {Banner} from '@primer/react/experimental'

import styles from './QuotaExceededBanner.module.css'

export function QuotaExceededBanner() {
  const {resetDate} = useEntitlement()
  return (
    <div className={styles.container}>
      <Banner
        variant="upsell"
        title="Limit reached soon"
        description={`You have reached your free plan limit. It will reset on ${resetDate}`}
        hideTitle
        primaryAction={
          <LinkButton
            as="a"
            href="https://github.com/features/copilot#pricing"
            onClick={() => {
              sendEvent('dotcom_chat.activate', {
                target: 'QUOTA_EXCEEDED_BANNER_LINK_UPGRADE',
                mode: 'immersive',
              })
            }}
          >
            Upgrade
          </LinkButton>
        }
      />
    </div>
  )
}
