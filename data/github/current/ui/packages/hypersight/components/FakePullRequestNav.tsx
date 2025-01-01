import {useCallback} from 'react'
import {useLocation} from 'react-router-dom'

import styles from './FakePullRequestNav.module.css'
import {TabNav} from '@primer/react/deprecated'
import {ChecklistIcon, CommentDiscussionIcon, CopilotIcon, FileDiffIcon, GitCommitIcon} from '@primer/octicons-react'
import {CounterLabel} from '@primer/react'
import type {NavigationUrls} from '../utils/types'
import {isFeatureEnabled} from '@github-ui/feature-flags'

interface PullRequestHeaderNavigationProps {
  urls: NavigationUrls
  commitsCount?: number
}

// This component approximates the PullRequestHeaderNavigationShared component from ui/packages/pull-requests/components/PullRequestHeaderNavigation.tsx
// This is a hack to render the hypersight page with a navigation bar that resembles the standard pull request pages.
// If hypersight ends up in PRs long-term, the pull-requests package should render hypersight directly, without this duplication.
export function FakePullRequestNav({commitsCount, urls}: PullRequestHeaderNavigationProps) {
  const location = useLocation()
  const isCurrentLocation = useCallback((url: string) => location.pathname === url, [location])
  const tabClasses = `position-relative px-3 flex-shrink-0 ${styles.muteWhenUnselected} ${styles.overrideLineHeight}`
  const iconClasses = 'fg-muted mr-2 d-none d-sm-inline-block'
  const walkthroughEnabled = isFeatureEnabled('hypersight')

  return (
    <div className="px-3">
      <TabNav aria-label="Pull request navigation tabs">
        <TabNav.Link href={urls.conversation} selected={isCurrentLocation(urls.conversation)} className={tabClasses}>
          <CommentDiscussionIcon className={iconClasses} />
          Conversation
        </TabNav.Link>
        <TabNav.Link href={urls.commits} selected={isCurrentLocation(urls.commits)} className={tabClasses}>
          <GitCommitIcon className={iconClasses} />
          Commits
          {typeof commitsCount === 'number' && <CounterLabel className="ml-2">{commitsCount}</CounterLabel>}
        </TabNav.Link>
        <TabNav.Link href={urls.checks} selected={isCurrentLocation(urls.checks)} className={tabClasses}>
          <ChecklistIcon className={iconClasses} />
          Checks
        </TabNav.Link>
        {walkthroughEnabled && (
          <TabNav.Link href={urls.walkthrough} selected={isCurrentLocation(urls.walkthrough)} className={tabClasses}>
            <CopilotIcon className={iconClasses} />
            Walkthrough
          </TabNav.Link>
        )}
        <TabNav.Link href={urls.files} selected={isCurrentLocation(urls.files)} className={tabClasses}>
          <FileDiffIcon className={iconClasses} />
          Files changed
        </TabNav.Link>
      </TabNav>
    </div>
  )
}
