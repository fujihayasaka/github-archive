import {UnderlineNav, IconButton} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {
  IssueOpenedIcon,
  ThreeBarsIcon,
  CodeIcon,
  GitPullRequestIcon,
  CommentDiscussionIcon,
  ShieldIcon,
  PlayIcon,
  ProjectIcon,
  GraphIcon,
  MarkGithubIcon,
} from '@primer/octicons-react'

import styles from './GlobalNavigation.module.css'

// 🚨 Note: This is a fake component mimicking our global navigation.

export default function GlobalNavigation() {
  return (
    <header className={styles.Box}>
      <div className={styles.Box_1}>
        {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
        <IconButton icon={ThreeBarsIcon} aria-label="Open global navigation menu" unsafeDisableTooltip />
        <Octicon icon={MarkGithubIcon} size={32} />
        <div className={styles.Box_2}>
          <span>primer</span>
          <span className={styles.Text}>/</span>
          <span className={styles.Text_1}>react</span>
        </div>
      </div>
      <UnderlineNav aria-label="Repository">
        <UnderlineNav.Item icon={CodeIcon}>Code</UnderlineNav.Item>
        <UnderlineNav.Item aria-current="page" icon={IssueOpenedIcon} counter={30}>
          Issues
        </UnderlineNav.Item>
        <UnderlineNav.Item icon={GitPullRequestIcon} counter={3}>
          Pull Requests
        </UnderlineNav.Item>
        <UnderlineNav.Item icon={CommentDiscussionIcon}>Discussions</UnderlineNav.Item>
        <UnderlineNav.Item icon={PlayIcon}>Actions</UnderlineNav.Item>
        <UnderlineNav.Item icon={ProjectIcon} counter={7}>
          Projects
        </UnderlineNav.Item>
        <UnderlineNav.Item icon={ShieldIcon} counter={12}>
          Security
        </UnderlineNav.Item>
        <UnderlineNav.Item icon={GraphIcon}>Insights</UnderlineNav.Item>
      </UnderlineNav>
    </header>
  )
}
