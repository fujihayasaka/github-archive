import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {PullRequestErrorState} from '../components/PullRequestErrorState'
import {SplitPageLayout} from '@primer/react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {PullRequestFileTree} from '@github-ui/pull-request-file-tree/PullRequestFileTree'
import {PullRequestFilesToolbar} from '@github-ui/pull-request-files-toolbar/PullRequestFilesToolbar'
import {PullRequestDiffsList} from '../components/PullRequestDiffsList'
import type {FilesRoutePayload} from '../page-data/payloads/files'
import type {DiffEntry} from '@github-ui/diff-lines'
import {useTreePane} from '@github-ui/commits/shared/useTreePane'
import {DIFF_FILE_TREE_ID} from '@github-ui/diff-file-tree/file-tree'
import {
  useDiffViewSettingsData,
  useSplitViewPreference,
  useWhitespacePreference,
} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'
import {useMemo, useState} from 'react'
import {getFileExtensions} from '@github-ui/diff-file-tree/diff-file-tree-helpers'
import {useFileFiltering, type FileFilterState} from '@github-ui/pull-request-file-tree/hooks/use-file-filtering'

export function FilesEntrypoint() {
  return (
    <ErrorBoundary critical fallback={<PullRequestErrorState text="Changes cannot be loaded" />}>
      <Files />
    </ErrorBoundary>
  )
}

export function Files() {
  const data = useRoutePayload<FilesRoutePayload>()

  return <FilesComponent {...data} />
}

export function FilesComponent(payload: FilesRoutePayload) {
  const {
    annotations,
    commits,
    diffSummaries,
    diffContents,
    pullRequest,
    repository,
    threadPreviews,
    user,
    viewerPendingReview,
  } = payload

  const userSplitPreference = useSplitViewPreference(user.viewSettings.splitPreference)
  const userWhitespaceParam = useWhitespacePreference(user.viewSettings.hideWhitespace)
  const viewSettingsData = useMemo(() => {
    return {
      hideWhitespace: userWhitespaceParam,
      splitPreference: userSplitPreference,
      lineSpacing: user.viewSettings.lineSpacing,
      commentsPreference: user.viewSettings.commentsPreference,
    }
  }, [user.viewSettings.commentsPreference, user.viewSettings.lineSpacing, userSplitPreference, userWhitespaceParam])

  const {data: settingsData} = useDiffViewSettingsData(viewSettingsData)

  const [fileFilterState, setFileFilterState] = useState<FileFilterState>(() => ({
    filterText: '',
    fileExtensions: getFileExtensions(diffSummaries),
    unselectedFileExtensions: new Set<string>(),
    showCodeowners: false,
    showDeletedFiles: true,
    showGeneratedFiles: true,
    showOnlyManifestFiles: false,
    showVendorFiles: true,
    showViewedFiles: true,
  }))

  const [diffHiddenMap, filteredDiffs] = useFileFiltering(diffSummaries, fileFilterState, pullRequest.pathName)

  const diffsEntries: DiffEntry[] = diffContents
    .filter(diff => diffHiddenMap.get(diff.path) !== true)
    .map(diff => {
      return {
        ...diff,
        helpUrl: '',
        repository,
        diffContext: 'pr',
        currentUser: {
          avatarURL: '', // TODO
          login: user.currentUserLogin || '',
          tabSize: undefined,
          splitPreference: settingsData?.splitPreference ?? 'unified',
          lineSpacing: settingsData?.lineSpacing ?? 'relaxed',
          canComment: true,
          commentsPreference: settingsData?.commentsPreference ?? 'visible',
        },
        collapsed: diff.reviewed,
        commentingEnabled: false,
        changeType: diff.status,
        // pullRequest, // TODO might need to do some mapping here
      }
    })
  // eventually we're going to the treeToggleElement and collapseTree returns from this hook too
  const {splitPagePaneHiddenSx, splitPageContentHidden} = useTreePane(DIFF_FILE_TREE_ID, user.isFileTreeExpanded)

  return (
    <>
      <SplitPageLayout.Pane
        position="start"
        sticky
        offsetHeader="80px" // sticky header height + a lil extra for spacing
        aria-label="File tree"
        padding="none"
        className="pr-3"
        sx={splitPagePaneHiddenSx}
        divider={{regular: 'line', narrow: 'none'}}
        widthStorageKey="diff-tree-pane-width"
        resizable
      >
        <PullRequestFileTree
          baseRefOid={pullRequest.comparison.baseOid}
          commits={commits}
          diffs={diffSummaries}
          ownerLogin={repository.ownerLogin}
          pathName={pullRequest.pathName}
          pullRequestId={pullRequest.globalRelayId}
          pullRequestNumber={pullRequest.number}
          repositoryName={repository.name}
          setFileFilterState={setFileFilterState}
          filteredDiffs={filteredDiffs}
          fileFilterState={fileFilterState}
        />
      </SplitPageLayout.Pane>
      <SplitPageLayout.Content as="div" width="full" hidden={splitPageContentHidden} padding="none">
        <PullRequestFilesToolbar
          annotations={annotations}
          copilotAccessAllowed={repository.copilotEnabled}
          currentUserLogin={user.currentUserLogin}
          isFileTreeExpanded={user.isFileTreeExpanded}
          pullRequest={pullRequest}
          repository={repository}
          shouldShowViewedFilesCount={user.shouldShowViewedFilesCount}
          totalFilesCount={diffSummaries.length}
          threadPreviews={threadPreviews}
          viewedFilesCount={user.viewedFilesCount}
          viewerPendingReview={viewerPendingReview}
          setFileFilterState={setFileFilterState}
          filteredDiffs={filteredDiffs}
          fileFilterState={fileFilterState}
        />
        <PullRequestDiffsList headBranchName={pullRequest.headBranch} diffs={diffsEntries} pullRequest={pullRequest} />
      </SplitPageLayout.Content>
    </>
  )
}
