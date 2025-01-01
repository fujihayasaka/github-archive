import {ViewedFileProgress} from './ViewedFileProgress'
import {OpenCommentsSidePanelButton} from './OpenCommentsSidePanelButton'
import {OpenAlertsPanelButton} from './OpenAlertsPanelButton'
import {ReviewMenuButton} from './ReviewMenuButton'
import {DiffViewSettings} from '@github-ui/diff-view-settings'
import {RefreshButton} from './RefreshButton'
import {Stack, Tooltip} from '@primer/react'
import {ChangesSelector} from '../diff-filtering/ChangesSelector'
import type {FilesRoutePayload, PageLimits} from '../../page-data/payloads/files'
import type {ViewedFilesCountPayload} from '../../page-data/payloads/viewed-files-count'
import type {CommentingImplementation} from '@github-ui/conversations'
import {useState} from 'react'
import stickyStyles from '@github-ui/use-sticky-header/use-sticky-header.module.css'
import {useIntersectionObserver} from '@github-ui/use-sticky-header/useIntersectionObserver'
import {ObservableBox as StickyHeaderActivationThreshold} from '@github-ui/use-sticky-header/ObservableBox'
import {PullRequestStateLabel} from '../PullRequestStateLabel'
import {clsx} from 'clsx'
import styles from './PullRequestFilesToolbar.module.css'
import {PullRequestHeaderSummary} from '../PullRequestHeaderSummary'
import {useHeaderPageData} from '../../page-data/loaders/use-header-page-data'
import {useHeaderLiveUpdates} from '../../hooks/use-header-live-updates'
import type {HeaderPageData} from '../../page-data/payloads/header'

// Height of the sticky header, change this if the height of the sticky header changes
export const STICKY_HEADER_HEIGHT = 62

export type PullRequestFilesToolbarProps = {
  commentBoxConfig: CommentingImplementation['commentBoxConfig']
  commentBoxSubject: CommentingImplementation['commentBoxSubject']
  commits: FilesRoutePayload['commits']
  currentUserLogin?: string
  diffEntries: FilesRoutePayload['diffContents']
  fileFilter: JSX.Element
  isFileTreeExpanded?: boolean
  lastReviewOid?: string
  pageLimits: PageLimits
  pullRequest: FilesRoutePayload['pullRequest']
  repository: FilesRoutePayload['repository']
  shouldShowViewedFilesCount: boolean
  threadPreviews: FilesRoutePayload['threadPreviews']
  totalFilesCount: number
  treeToggleElement?: JSX.Element
  viewedFilesCount: ViewedFilesCountPayload['viewedFilesCount']
}

export function LivePullRequestFilesToolbar({
  aliveChannel,
  repository,
  pullRequest: initialPullRequest,
  bannersData,
  urls,
  user,
  ...pullRequestFilesToolbarProps
}: PullRequestFilesToolbarProps & HeaderPageData) {
  const {
    data: {pullRequest},
  } = useHeaderPageData()
  useHeaderPageData({aliveChannel, repository, pullRequest: initialPullRequest, bannersData, urls, user})
  useHeaderLiveUpdates(aliveChannel)

  const updatedPullRequest = {...initialPullRequest, ...pullRequest} as FilesRoutePayload['pullRequest']

  return (
    <PullRequestFilesToolbar
      repository={repository}
      pullRequest={updatedPullRequest}
      {...pullRequestFilesToolbarProps}
    />
  )
}

export function PullRequestFilesToolbar({
  commentBoxConfig,
  commentBoxSubject,
  commits,
  currentUserLogin,
  diffEntries,
  fileFilter,
  isFileTreeExpanded,
  lastReviewOid,
  pageLimits,
  pullRequest,
  repository,
  shouldShowViewedFilesCount,
  threadPreviews,
  totalFilesCount,
  treeToggleElement,
  viewedFilesCount,
}: PullRequestFilesToolbarProps) {
  const [isSticky, setIsSticky] = useState(false)
  const basePath = pullRequest.pathName
  const showDivider = shouldShowViewedFilesCount || !isFileTreeExpanded

  const [observe, unobserve] = useIntersectionObserver(entries => {
    if (entries[0]) {
      setIsSticky(!entries[0].isIntersecting)
    }
  })

  return (
    <>
      <StickyHeaderActivationThreshold
        sx={{visibility: 'hidden', height: '1px'}}
        onObserve={observe}
        onUnobserve={unobserve}
      />
      <Stack
        as="section"
        direction="horizontal"
        justify="space-between"
        gap="condensed"
        align="center"
        className={clsx(stickyStyles.stickyHeader, styles.toolbar, isSticky && styles['is-stuck'])}
      >
        <h2 className="sr-only">Pull Request Toolbar</h2>

        <Stack direction="horizontal" gap="condensed" align="center" className="min-width-0">
          <div>{treeToggleElement}</div>
          <div className={styles['show-when-stuck']}>
            <PullRequestStateLabel state={pullRequest.state} />
          </div>
          <div className={styles['hide-when-stuck']}>
            <ChangesSelector
              commits={commits}
              lastReviewOid={lastReviewOid}
              ownerLogin={repository.ownerLogin}
              pullRequestNumber={pullRequest.number}
              repositoryName={repository.name}
            />
          </div>
          <Stack direction="vertical" gap="none" className={clsx(styles['show-when-stuck'], 'min-width-0')}>
            <div className="d-flex mb-n1">
              <Tooltip type="label" direction="s" text={pullRequest.title}>
                <a href="#top" className="d-flex overflow-hidden fgColor-default">
                  <bdi className={clsx('f5 text-bold overflow-hidden no-wrap', styles['pr-sticky-title'])}>
                    {pullRequest.title}
                  </bdi>
                </a>
              </Tooltip>
              <span className="f5 text-normal pl-2 fgColor-muted d-inline">#{pullRequest.number}</span>
            </div>
            <div className="f6 text-normal d-flex flex-items-center ml-n2">
              <ChangesSelector
                commits={commits}
                lastReviewOid={lastReviewOid}
                ownerLogin={repository.ownerLogin}
                pullRequestNumber={pullRequest.number}
                repositoryName={repository.name}
                variant="condensed"
              />
              <div className="d-none d-xl-flex flex-items-center min-width-0">
                <div className="border-left mx-1 pr-1 d-block" style={{width: '1px', height: '16px'}} />
                <PullRequestHeaderSummary
                  author={pullRequest.author.login}
                  baseBranch={pullRequest.baseBranch}
                  baseRepositoryOwnerLogin={repository.ownerLogin}
                  baseRepositoryName={repository.name}
                  commitsCount={pullRequest.commitsCount}
                  headBranch={pullRequest.headBranch}
                  headRepositoryOwnerLogin={pullRequest.headRepositoryOwnerLogin}
                  headRepositoryName={pullRequest.headRepositoryName}
                  isInAdvisoryRepo={pullRequest.isInAdvisoryRepo}
                  mergedBy={pullRequest.mergedBy}
                  state={pullRequest.state}
                />
              </div>
            </div>
          </Stack>
        </Stack>
        <Stack direction="horizontal" align="center">
          <RefreshButton aliveChannel={pullRequest.aliveChannel} pathName={basePath} />

          {shouldShowViewedFilesCount && (
            <ViewedFileProgress
              pullRequest={pullRequest}
              totalFilesCount={totalFilesCount}
              viewedFilesCount={viewedFilesCount}
            />
          )}

          {!isFileTreeExpanded && fileFilter}

          {showDivider && <div className="border-left mx-1 d-block" style={{width: '1px', height: '28px'}} />}

          <OpenCommentsSidePanelButton
            commentBoxConfig={commentBoxConfig}
            pageLimits={pageLimits}
            pullRequest={pullRequest}
            threadPreviews={threadPreviews}
            repositoryId={repository.id}
          />
          <OpenAlertsPanelButton basePath={basePath} pageLimits={pageLimits} />
          {currentUserLogin && (
            <ReviewMenuButton
              commentBoxConfig={commentBoxConfig}
              commentBoxSubject={commentBoxSubject}
              currentUserLogin={currentUserLogin}
              diffEntries={diffEntries}
              pullRequest={pullRequest}
              repository={repository}
            />
          )}
          <DiffViewSettings invisible={false} reloadOnWhitespaceChange small />
        </Stack>
      </Stack>
    </>
  )
}
