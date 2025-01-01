import {Spinner} from '@primer/react'

import styles from './EditorLoadingSpinner.module.css'

export function EditorLoadingSpinner() {
  return (
    <div className={styles.Box}>
      <Spinner />
    </div>
  )
}
