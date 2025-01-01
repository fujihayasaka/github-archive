import {SearchIcon} from '@primer/octicons-react'
import {Octicon} from '@primer/react/deprecated'

import styles from './FilterInputIcon.module.css'

export const FilterInputIcon = () => {
  return (
    <div className={styles.Box_0}>
      <Octicon icon={SearchIcon} aria-label="Search" className={styles.Octicon_0} />
    </div>
  )
}
