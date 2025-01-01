import {Octicon} from '@primer/react/deprecated'
import {PeopleIcon} from '@primer/octicons-react'

import styles from './SidebarSocialStats.module.css'

function ResponsiveSocialStats() {
  return (
    <div className={styles.Box}>
      <Octicon icon={PeopleIcon} size={16} className={styles.Octicon} />
      2450 <span className={styles.Box_1}>followers</span> <span className={styles.Box_2}>·</span> 10{' '}
      <span className={styles.Box_1}>following</span>
    </div>
  )
}

export default ResponsiveSocialStats
