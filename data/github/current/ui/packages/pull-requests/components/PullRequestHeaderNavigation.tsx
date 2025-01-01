import {ChecklistIcon, CommentDiscussionIcon, CopilotIcon, FileDiffIcon, GitCommitIcon} from '@primer/octicons-react'
import {CounterLabel} from '@primer/react'
import {TabNav} from '@primer/react/deprecated'
import {useLocation} from 'react-router-dom'

import styles from './PullRequestHeaderNavigation.module.css'
import {useCallback} from 'react'
import {clsx} from 'clsx'
import {useTabCountsPageData} from '../page-data/loaders/use-tab-counts-page-data'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {pullRequestsCommitsRoute} from '../routes/commits-route'
import {useIsDataRouterEnabled} from '@github-ui/react-core/future/use-is-data-router-enabled'
import type {NavigationCounterPageData} from '../page-data/payloads/tab-counts'
import type {NavigationUrls} from './NavigationUrls'
import {isFeatureEnabled} from '@github-ui/feature-flags'

interface PullRequestHeaderNavigationProps {
  commitsCount?: number
  urls: NavigationUrls
}

export function PullRequestHeaderNavigation({commitsCount, urls}: PullRequestHeaderNavigationProps) {
  const isDataRouter = useIsDataRouterEnabled()
  if (isDataRouter) {
    return <PullRequestHeaderNavigationData commitsCount={commitsCount} urls={urls} />
  }
  return <PullRequestHeaderNavigationNavigator commitsCount={commitsCount} urls={urls} />
}

function PullRequestHeaderNavigationNavigator({commitsCount, urls}: PullRequestHeaderNavigationProps) {
  const {data: labelCounts} = useTabCountsPageData()

  return <PullRequestHeaderNavigationShared labelCounts={labelCounts} commitsCount={commitsCount} urls={urls} />
}

function PullRequestHeaderNavigationData({commitsCount, urls}: PullRequestHeaderNavigationProps) {
  const {data: labelCounts} = useRouteQuery(pullRequestsCommitsRoute, 'tabCounts')

  return <PullRequestHeaderNavigationShared labelCounts={labelCounts} commitsCount={commitsCount} urls={urls} />
}

function PullRequestHeaderNavigationShared({
  commitsCount,
  urls,
  labelCounts,
}: PullRequestHeaderNavigationProps & {
  labelCounts: NavigationCounterPageData | undefined
}) {
  const location = useLocation()
  const isCurrentLocation = useCallback((url: string) => location.pathname === url, [location])
  const tabClasses = `position-relative px-3 flex-shrink-0 ${styles.muteWhenUnselected} ${styles.overrideLineHeight}`

  const iconClasses = 'fg-muted mr-2 d-none d-sm-inline-block'

  const asyncCounterClasses = clsx('ml-2', labelCounts ? '' : styles.counterLoading)
  const walkthroughEnabled = isFeatureEnabled('hypersight')

  return (
    <TabNav aria-label="Pull request navigation tabs">
      <TabNav.Link href={urls.conversation} selected={isCurrentLocation(urls.conversation)} className={tabClasses}>
        <CommentDiscussionIcon className={iconClasses} />
        Conversation
        {typeof labelCounts?.conversationCount === 'number' && (
          <CounterLabel className={asyncCounterClasses}>{labelCounts.conversationCount}</CounterLabel>
        )}
      </TabNav.Link>
      <TabNav.Link href={urls.commits} selected={isCurrentLocation(urls.commits)} className={tabClasses}>
        <GitCommitIcon className={iconClasses} />
        Commits
        {typeof commitsCount === 'number' && <CounterLabel className="ml-2">{commitsCount}</CounterLabel>}
      </TabNav.Link>
      <TabNav.Link href={urls.checks} selected={isCurrentLocation(urls.checks)} className={tabClasses}>
        <ChecklistIcon className={iconClasses} />
        Checks
        {typeof labelCounts?.checksCount === 'number' && (
          <CounterLabel className={asyncCounterClasses}>{labelCounts.checksCount}</CounterLabel>
        )}
      </TabNav.Link>
      <TabNav.Link href={urls.files} selected={isCurrentLocation(urls.files)} className={tabClasses}>
        <FileDiffIcon className={iconClasses} />
        Files changed
        {labelCounts && labelCounts.filesChangedCount ? (
          <CounterLabel className={asyncCounterClasses}>{labelCounts.filesChangedCount}</CounterLabel>
        ) : null}
      </TabNav.Link>
      {walkthroughEnabled && (
        <TabNav.Link href={urls.walkthrough} selected={isCurrentLocation(urls.walkthrough)} className={tabClasses}>
          <CopilotIcon className={iconClasses} />
          Walkthrough
        </TabNav.Link>
      )}
    </TabNav>
  )
}
