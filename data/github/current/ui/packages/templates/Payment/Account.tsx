// eslint-disable-next-line no-restricted-imports
import {Button, Avatar, Heading} from '@primer/react'
import {ArrowSwitchIcon} from '@primer/octicons-react'

import styles from './Account.module.css'

function Account() {
  return (
    <div className={styles.Box}>
      <div className={styles.Box_1}>
        <Heading as="h2" className={styles.Heading}>
          Account
        </Heading>
        <Button size="small" leadingVisual={ArrowSwitchIcon} aria-label="Switch account">
          Switch
        </Button>
      </div>
      <div className={styles.Box_2}>
        <div className={styles.Box_3}>
          <Avatar
            square
            size={40}
            src="https://github.com/primer/react/assets/980622/99c92b77-11ec-4553-a7b4-c5759b70028e"
            className={styles.Avatar_0}
          />
          <div className={styles.Box_4}>
            <span className={styles.Text}>Mojang</span>
            <span className={styles.Text_1}>Mojang Studios Inc. (Stockholm)</span>
          </div>
        </div>
      </div>
    </div>
  )
}

export default Account
