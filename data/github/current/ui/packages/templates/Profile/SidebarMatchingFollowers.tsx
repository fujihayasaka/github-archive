// eslint-disable-next-line no-restricted-imports
import {Avatar, Link} from '@primer/react'

import styles from './SidebarMatchingFollowers.module.css'

function SidebarMatchingFollowers() {
  return (
    <div className={styles.Box}>
      <Avatar src="https://avatars.githubusercontent.com/u/980622?v=4" className={styles.Avatar_0} />
      <span className={styles.Text}>
        Followed by{' '}
        <Link href="https://github.com/maximedegreve" inline muted className={styles.Link}>
          maximedegreve
        </Link>{' '}
        and 8 more
      </span>
    </div>
  )
}

export default SidebarMatchingFollowers
