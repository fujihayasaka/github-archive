import {ExpandButton} from '@github-ui/expand-button'
import React, {useCallback, useEffect} from 'react'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {ssrSafeDocument} from '@github-ui/ssr-utils'

import {ViewedFileProgress} from './components/ViewedFileProgress'
import type {ToolbarPayload} from './page-data/payloads/toolbar'
import {OpenCommentsSidePanelButton} from './components/OpenCommentsSidePanelButton'
import {OpenAnnotationsPanelButton} from './components/OpenAnnotationsPanelButton'
import {ReviewMenuButton} from './components/ReviewMenuButton'
import {CopilotDiffChatHeaderMenu} from '@github-ui/copilot-code-chat/CopilotDiffChatHeaderMenu'
import {DiffViewSettings} from '@github-ui/diff-view-settings'
import {userPRFileTreeVisibilitySettingPath} from '@github-ui/paths'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {PullRequestFileTree} from '@github-ui/pull-request-file-tree/PullRequestFileTree'
import {usePullRequestFileTreePageData} from '@github-ui/pull-request-file-tree/PullRequestFileTreePayload'
import {threadPreviewsQueryKey} from './page-data/payloads/thread-previews'
import {viewedFilesCountQueryKey} from './page-data/payloads/viewed-files-count'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {RefreshButton} from './components/RefreshButton'
import {pendingReviewQueryKey} from './page-data/payloads/pending-review'
import type {FileFilterState} from '@github-ui/pull-request-file-tree/hooks/use-file-filtering'
import type {DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'

export interface PullRequestFilesToolbarProps {
  toolbarPayload: ToolbarPayload
  stackingBreakpoint?: 'md' | 'lg'
}

export function PullRequestFilesToolbar({
  annotations,
  copilotAccessAllowed,
  currentUserLogin,
  isFileTreeExpanded,
  pullRequest,
  repository,
  shouldShowViewedFilesCount,
  totalFilesCount,
  threadPreviews,
  viewedFilesCount,
  viewerPendingReview,
  stackingBreakpoint = 'md',
  fileFilterState,
  setFileFilterState,
  filteredDiffs,
}: ToolbarPayload & {
  repository: ToolbarPayload['pullRequest']['repository']
  stackingBreakpoint?: 'md' | 'lg'
  fileFilterState: FileFilterState
  setFileFilterState: (state: FileFilterState) => void
  filteredDiffs: DiffDelta[]
}) {
  const [expanded, setExpanded] = React.useState(isFileTreeExpanded) // TODO - read from local storage?
  const [mobileExpanded, setMobileExpanded] = React.useState(false) // mobile collapsed by default

  const handleRailsEvents = useCallback(
    (event: Event) => {
      const {detail} = event as CustomEvent
      switch (detail) {
        case PageData.threadPreviews: {
          getQueryClient().invalidateQueries({
            queryKey: threadPreviewsQueryKey(pullRequest.pathName),
          })
          break
        }
        case PageData.viewedFilesCount: {
          getQueryClient().invalidateQueries({
            queryKey: viewedFilesCountQueryKey(pullRequest.pathName),
          })
          break
        }
        case PageData.pendingReview: {
          getQueryClient().invalidateQueries({
            queryKey: pendingReviewQueryKey(pullRequest.pathName),
          })
          break
        }
      }
    },
    [pullRequest.pathName],
  )

  useEffect(() => {
    // Uses custom events defined in ui/packages/pull-request-files-toolbar/page-data/rails-action-event.ts and used in Rails TS files
    ssrSafeDocument?.addEventListener('rails-action-event', handleRailsEvents)

    return () => ssrSafeDocument?.removeEventListener('rails-action-event', handleRailsEvents)
  }, [handleRailsEvents])

  const onToggleExpanded = () => {
    const fileTree = document.getElementById('diff-layout-component')
    if (fileTree) {
      const nextExpandedState = !expanded
      setExpanded(currentExpanded => !currentExpanded)

      fileTree.classList.toggle('hx_Layout--sidebar-hidden', !nextExpandedState)

      // we only update the user pref when not mobile
      if (currentUserLogin) {
        const formData = new FormData()
        formData.set('file_tree_visible', nextExpandedState ? 'true' : 'false')

        verifiedFetch(userPRFileTreeVisibilitySettingPath({login: currentUserLogin}), {
          method: 'PUT',
          body: formData,
          headers: {Accept: 'application/json'},
        })
      }
    }
  }

  const onMobileToggleExpanded = () => {
    const fileTree = document.getElementById('diff-layout-component')
    if (fileTree) {
      setMobileExpanded(!mobileExpanded)
    }
  }

  const onFileSelected = () => {
    setMobileExpanded(false)
  }

  return (
    <PageDataContextProvider basePageDataUrl={pullRequest.pathName}>
      <section
        className="d-flex flex-justify-between flex-items-center pb-2 bgColor-default pt-2 mt-n2"
        id="react-partial-pull-requests-files-toolbar"
      >
        <h2 className="sr-only">Pull Request Toolbar</h2>
        <div>
          <ExpandButton
            alignment="left"
            ariaLabel={expanded ? 'Collapse file tree' : 'Expand file tree'}
            ariaControls="pr-file-tree"
            expanded={expanded}
            onToggleExpanded={onToggleExpanded}
            testid="pr-file-tree-expand-button"
            className={`d-none d-${stackingBreakpoint}-block`}
          />
          <ExpandButton
            alignment="left"
            ariaLabel={mobileExpanded ? 'Collapse file tree' : 'Expand file tree'}
            ariaControls="pr-file-tree"
            expanded={mobileExpanded}
            onToggleExpanded={onMobileToggleExpanded}
            testid="pr-file-tree-expand-button-mobile"
            className={`d-block d-${stackingBreakpoint}-none`}
          />
        </div>
        <div className="d-flex flex-items-center gap-2">
          <RefreshButton aliveChannel={pullRequest.aliveChannel} pathName={pullRequest.pathName} />
          {shouldShowViewedFilesCount && (
            <ViewedFileProgress
              pullRequest={pullRequest}
              totalFilesCount={totalFilesCount}
              viewedFilesCount={viewedFilesCount}
            />
          )}
          <OpenCommentsSidePanelButton
            pullRequest={pullRequest}
            threadPreviews={threadPreviews}
            repositoryId={repository.id}
          />
          <OpenAnnotationsPanelButton annotations={annotations} />
          {copilotAccessAllowed && (
            <CopilotDiffChatHeaderMenu
              prPathName={pullRequest.pathName}
              baseOid={pullRequest.comparison.baseOid}
              headOid={pullRequest.comparison.headOid}
            />
          )}
          {currentUserLogin && (
            <ReviewMenuButton
              currentUserLogin={currentUserLogin}
              initialPendingReview={viewerPendingReview}
              pullRequest={pullRequest}
              repository={repository}
            />
          )}
          <DiffViewSettings invisible={false} reloadOnWhitespaceChange small />
        </div>
      </section>
      {mobileExpanded && (
        <div className={`d-block d-${stackingBreakpoint}-none`}>
          <PullRequestFileTreeWrapper
            fileFilterState={fileFilterState}
            setFileFilterState={setFileFilterState}
            filteredDiffs={filteredDiffs}
            pathName={pullRequest.pathName}
            onFileSelected={onFileSelected}
          />
        </div>
      )}
    </PageDataContextProvider>
  )
}

function PullRequestFileTreeWrapper({
  pathName,
  onFileSelected,
  fileFilterState,
  setFileFilterState,
  filteredDiffs,
}: {
  pathName: string
  onFileSelected: () => void
  fileFilterState: FileFilterState
  setFileFilterState: (state: FileFilterState) => void
  filteredDiffs: DiffDelta[]
}) {
  const {data} = usePullRequestFileTreePageData({
    pathName,
  })

  if (!data) {
    return null
  }

  return (
    <PullRequestFileTree
      {...data}
      onFileSelected={onFileSelected}
      fileFilterState={fileFilterState}
      setFileFilterState={setFileFilterState}
      filteredDiffs={filteredDiffs}
    />
  )
}
