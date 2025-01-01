import {Navigation} from '@github-ui/copilot-chat/components/immersive/Navigation'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {ArrowUpRightIcon, SparkleFillIcon} from '@primer/octicons-react'

import {SPARK_PATH, SPARK_PLUGIN_ID} from '../utils/constants'
import styles from './SparkNavigation.module.css'

export function SparkNavigation() {
  return (
    <Navigation
      aria-current={ssrSafeLocation.pathname === SPARK_PATH ? 'page' : undefined}
      displayName="Spark"
      href={SPARK_PATH}
      icon={SparkleFillIcon}
      id={SPARK_PLUGIN_ID}
      contextMenuComponent={<ArrowUpRightIcon className={styles.trailingVisual} />}
    />
  )
}
