import {IconButton, UnderlineNav} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {
  StarIcon,
  BookIcon,
  RepoIcon,
  ProjectIcon,
  PackageIcon,
  ThreeBarsIcon,
  MarkGithubIcon,
} from '@primer/octicons-react'

import styles from './Navigation.module.css'

// 🚨 Note: This is a fake component mimicking our global navigation.

function Navigation() {
  return (
    <header className={styles.Box}>
      <div className={styles.Box_1}>
        {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
        <IconButton unsafeDisableTooltip icon={ThreeBarsIcon} aria-label="Open global navigation menu" />
        <Octicon icon={MarkGithubIcon} size={32} />
        <div className={styles.Box_2}>
          <span className={styles.Text}>mona</span>
        </div>
      </div>
      <UnderlineNav aria-label="User">
        <UnderlineNav.Item aria-current="page" icon={BookIcon}>
          Overview
        </UnderlineNav.Item>
        <UnderlineNav.Item icon={RepoIcon} counter={25}>
          Repositories
        </UnderlineNav.Item>
        <UnderlineNav.Item icon={ProjectIcon}>Projects</UnderlineNav.Item>
        <UnderlineNav.Item icon={PackageIcon}>Packages</UnderlineNav.Item>
        <UnderlineNav.Item icon={StarIcon} counter={28}>
          Stars
        </UnderlineNav.Item>
      </UnderlineNav>
    </header>
  )
}

export default Navigation
