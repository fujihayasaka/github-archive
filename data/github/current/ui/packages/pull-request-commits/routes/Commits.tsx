import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Commits as CommitsList} from '@github-ui/commits/shared/Commits'
import {CommitsBlankState} from '@github-ui/commits/shared/CommitsBlankState'
import {useAnalytics} from '@github-ui/use-analytics'

import {LivePullRequestHeader} from '../components/PullRequestHeader'
import {PageLayout, Flash} from '@primer/react'
import {useCommitsLiveUpdates} from '../hooks/use-commits-live-updates'
import {useCommitsPageData} from '../page-data/loaders/use-commits-page-data'
import {ObservableBox as StickyHeaderActivationThreshold} from '@github-ui/use-sticky-header/ObservableBox'
import {useStickyHeader} from '@github-ui/use-sticky-header/useStickyHeader'
import {responsiveWrapperClasses, StickyPullRequestHeader} from '../components/StickyPullRequestHeader'
import type {HeaderPageData} from '../page-data/payloads/header'
import type {CommitsPageData} from '../page-data/payloads/commits'
import {useLoadDeferredCommitDataPaginated} from '@github-ui/commits/shared/useLoadDeferredCommitData'
import {useEffect} from 'react'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {PullRequestCommitErrorState} from '../components/PullRequestCommitErrorState'

export type CommitsRoutePayload = CommitsPageData &
  HeaderPageData & {
    metadata: {
      deferredCommitsDataUrl: string
      aliveChannel: string
    }
  }

const loggingPrefix = 'prx_commits.'

export function CommitsEntrypoint() {
  return (
    <ErrorBoundary critical fallback={<PullRequestCommitErrorState />}>
      <Commits />
    </ErrorBoundary>
  )
}

export function Commits() {
  const {
    commitGroups,
    metadata: {deferredCommitsDataUrl, aliveChannel},
    pullRequest,
    bannersData,
    repository,
    timeOutMessage,
    truncated,
    urls,
    user,
  } = useRoutePayload<CommitsRoutePayload>()

  const {isSticky, observe, unobserve} = useStickyHeader()
  const {data: commitsData, dataUpdatedAt} = useCommitsPageData({
    commitGroups,
    repository,
    timeOutMessage,
    truncated,
  })

  useCommitsLiveUpdates(aliveChannel)
  const deferredCommitsData = useLoadDeferredCommitDataPaginated(
    deferredCommitsDataUrl,
    //currently passing in 0 to start at the beginning, but if we want to paginate in the future this would be a variable
    0,
    pullRequest.commitsCount,
    dataUpdatedAt,
  )
  const {sendAnalyticsEvent} = useAnalytics()

  const loggingInfo = {commitCount: pullRequest.commitsCount, prNumber: pullRequest.number}

  useEffect(() => {
    sendAnalyticsEvent(`${loggingPrefix}page_view`, 'COMMITS_PAGE_VIEWED', loggingInfo)
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <>
      {isSticky && <StickyPullRequestHeader repository={repository} pullRequest={pullRequest} />}
      <div className={`mt-4 ${responsiveWrapperClasses}`}>
        <PageLayout padding="none">
          <PageLayout.Header>
            <LivePullRequestHeader
              aliveChannel={aliveChannel}
              repository={repository}
              pullRequest={pullRequest}
              bannersData={bannersData}
              urls={urls}
              user={user}
            />
            {/* On scroll, when this element reaches the top of the viewport, the sticky header activates */}
            <StickyHeaderActivationThreshold
              sx={{visibility: 'hidden', height: '1px'}}
              onObserve={observe}
              onUnobserve={unobserve}
            />
          </PageLayout.Header>

          <h2 className="sr-only">Commits</h2>

          <PageLayout.Content as="div">
            <div data-testid="commits-list" data-hpc>
              <ErrorBoundary critical fallback={<PullRequestCommitErrorState />}>
                {commitsData.commitGroups.length === 0 && (
                  <CommitsBlankState timeoutMessage={commitsData.timeOutMessage} />
                )}
                {commitsData.commitGroups.length > 0 && (
                  <>
                    {commitsData.truncated && (
                      <Flash variant="warning" className="mb-3">
                        This pull request is big! We&apos;re only showing the most recent 250 commits
                      </Flash>
                    )}
                    <CommitsList
                      commitGroups={commitsData.commitGroups}
                      deferredCommitData={deferredCommitsData}
                      repository={commitsData.repository}
                      loggingPrefix={loggingPrefix}
                      loggingPayload={loggingInfo}
                    />
                  </>
                )}
              </ErrorBoundary>
            </div>
          </PageLayout.Content>
        </PageLayout>
      </div>
    </>
  )
}
