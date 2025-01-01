/*
 * Shown when user accounts have billing issues.
 */

import {Link} from '@primer/react'
import {Banner} from '@primer/react/experimental'

import styles from './Banner.module.css'

export function CopilotBillingBanner() {
  const description = (
    <>
      We are having a problem billing your account. Please{' '}
      <Link inline href="https://github.com/settings/billing/budgets/new" target="_blank" rel="noopener noreferrer">
        update your payment method
      </Link>{' '}
      to keep Copilot Pro limits available on Spark.
    </>
  )
  const title = 'Billing issue with your account.'
  const variant = 'critical'

  return <Banner className={styles.SparkBanner} description={description} hideTitle title={title} variant={variant} />
}
