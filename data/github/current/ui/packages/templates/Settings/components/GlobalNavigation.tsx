import {IconButton} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {ThreeBarsIcon, MarkGithubIcon} from '@primer/octicons-react'

import styles from './GlobalNavigation.module.css'

// 🚨 Note: This is a fake component mimicking our global navigation.

function GlobalNavigation() {
  return (
    <header className={styles.Box}>
      <div className={styles.Box_1}>
        {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
        <IconButton unsafeDisableTooltip icon={ThreeBarsIcon} aria-label="Menu" />
        <Octicon icon={MarkGithubIcon} size={32} />
        <div className={styles.Box_2}>
          <span className={styles.Text}>Settings</span>
        </div>
      </div>
    </header>
  )
}

export default GlobalNavigation
