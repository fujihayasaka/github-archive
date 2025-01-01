import {IconButton} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {ThreeBarsIcon, MarkGithubIcon} from '@primer/octicons-react'

import styles from './GlobalNavigation.module.css'

export default function GlobalNavigation() {
  return (
    <header className={styles.Box}>
      <div className={styles.Box_1}>
        {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
        <IconButton icon={ThreeBarsIcon} aria-label="Open global navigation menu" unsafeDisableTooltip />
        <Octicon icon={MarkGithubIcon} size={32} />
        <div className={styles.Box_2}>
          <span className={styles.Text}>Marketplace</span>
        </div>
      </div>
    </header>
  )
}
