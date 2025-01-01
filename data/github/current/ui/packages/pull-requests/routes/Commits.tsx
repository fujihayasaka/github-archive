import {Commits as CommitsList} from '@github-ui/commits/shared/Commits'
import {CommitsBlankState} from '@github-ui/commits/shared/CommitsBlankState'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useAnalytics} from '@github-ui/use-analytics'

import {useLoadDeferredCommitDataPaginated} from '@github-ui/commits/shared/useLoadDeferredCommitData'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {Flash, SplitPageLayout} from '@primer/react'
import {useEffect} from 'react'
import {PullRequestErrorState} from '../components/PullRequestErrorState'
import {useCommitsLiveUpdates} from '../hooks/use-commits-live-updates'
import {useCommitsPageData} from '../page-data/loaders/use-commits-page-data'
import type {CommitsPageData} from '../page-data/payloads/commits'
import type {HeaderPageData} from '../page-data/payloads/header'

export type CommitsRoutePayload = CommitsPageData &
  HeaderPageData & {
    metadata: {
      deferredCommitsDataUrl: string
    }
  }

const loggingPrefix = 'prx_commits.'

export function CommitsEntrypoint() {
  return (
    <ErrorBoundary critical fallback={<PullRequestErrorState text="Commits cannot be loaded" />}>
      <Commits />
    </ErrorBoundary>
  )
}

export function Commits(props: {aliveChannelThrottleTimeout?: number}) {
  const data = useRoutePayload<CommitsRoutePayload>()

  return <CommitsComponent {...data} {...props} />
}

export function CommitsComponent({
  commitGroups,
  metadata: {deferredCommitsDataUrl},
  aliveChannel,
  pullRequest,
  repository,
  timeOutMessage,
  truncated,
  aliveChannelThrottleTimeout,
}: Pick<
  CommitsRoutePayload,
  'commitGroups' | 'pullRequest' | 'repository' | 'timeOutMessage' | 'truncated' | 'aliveChannel'
> & {
  metadata: Pick<CommitsRoutePayload['metadata'], 'deferredCommitsDataUrl'>
} & {
  aliveChannelThrottleTimeout?: number
}) {
  const {data: commitsData, dataUpdatedAt} = useCommitsPageData({
    commitGroups,
    repository,
    timeOutMessage,
    truncated,
  })

  useCommitsLiveUpdates(aliveChannel, aliveChannelThrottleTimeout)
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
      <h2 className="sr-only">Commits</h2>

      <SplitPageLayout.Content as="div" width="full" padding="none">
        <div data-testid="commits-list" data-hpc>
          {commitsData.commitGroups.length === 0 && <CommitsBlankState timeoutMessage={commitsData.timeOutMessage} />}
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
        </div>
      </SplitPageLayout.Content>
    </>
  )
}
