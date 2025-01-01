/*
 * Shown in case Azure Container Instances are at capacity.
 * This is a temporary state that should be resolved automatically.
 */

import {Banner} from '@primer/react/experimental'

import styles from './Banner.module.css'

export function SparkInfraLimitBanner() {
  const description = 'Spark is currently at capacity. Editing sparks is temporarily disabled. Please try again later.'
  const title = 'Spark editor is at capacity.'
  const variant = 'info'

  return <Banner className={styles.SparkBanner} description={description} hideTitle title={title} variant={variant} />
}
