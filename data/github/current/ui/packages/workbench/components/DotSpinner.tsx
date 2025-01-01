import {DotFillIcon} from '@primer/octicons-react'
import {Spinner} from '@primer/react'

import styles from './DotSpinner.module.css'

export const DotSpinner = () => {
  return (
    <div className={styles.dotSpinner}>
      <Spinner size="small" className={styles.spinner} />
      <DotFillIcon className={styles.pendingIcon} />
    </div>
  )
}
