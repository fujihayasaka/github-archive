import {Spinner} from '@primer/react'

import styles from './LoadingState.module.css'

export function LoadingState() {
  return (
    <div className={styles.container}>
      <Spinner size="large" />
    </div>
  )
}
