/*
 * Shown when the maximum viewer limit is reached on published Sparks.
 */

import {Link} from '@primer/react'
import {Banner} from '@primer/react/experimental'

import styles from './Banner.module.css'

export function RuntimeLimitBanner() {
  const description = (
    <>
      You have reached your monthly consumption limit for deployed sparks. If you would like to request a higher limit,{' '}
      <Link inline href="https://gh.io/spark-higher-limits-request" target="_blank" rel="noopener noreferrer">
        contact our team
      </Link>
      .
    </>
  )
  const title = 'Maximum viewer limit reached.'
  const variant = 'warning'

  return <Banner className={styles.SparkBanner} description={description} hideTitle title={title} variant={variant} />
}
