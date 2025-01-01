import {useEntitlement} from '@github-ui/copilot-chat/components/quota/EntitlementContext'
import {sendEvent} from '@github-ui/hydro-analytics'
import {Link, LinkButton} from '@primer/react'

import styles from './QuotaExceededEmptyState.module.css'

export function QuotaExceededEmptyState() {
  const {resetDate} = useEntitlement()
  return (
    <div className={styles.container}>
      <div className={styles.main}>
        <img className={styles.hero} src="/images/modules/copilot-immersive-v1/hero.png" alt="Hero" />
        <div className={styles.copy}>
          <h2 className={styles.heading}>You’ve reached your free plan limit</h2>
          <p className={styles.description}>Your limits will reset on {resetDate}.</p>
          <LinkButton
            as="a"
            variant="primary"
            size="large"
            href="https://github.com/features/copilot#pricing"
            onClick={() => {
              sendEvent('dotcom_chat.activate', {
                target: 'QUOTA_EXCEEDED_EMPTY_STATE_LINK_UPGRADE',
                mode: 'immersive',
              })
            }}
          >
            Upgrade to Pro
          </LinkButton>
        </div>
      </div>
      <div className={styles.footer}>
        <strong>Part of an organization?</strong>
        <span>
          Upgrade to{' '}
          <Link
            href="https://github.com/github-copilot/business_signup/choose_business_type?cft=copilot_li.features_copilot.cfb"
            inline
          >
            Copilot Business
          </Link>{' '}
          to enable across teams.
        </span>
      </div>
    </div>
  )
}
