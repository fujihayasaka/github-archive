import type {RepoSubject} from '@github-ui/comment-box/subject'
import {useTreePane} from '@github-ui/commits/shared/useTreePane'
import type {CommentingImplementation} from '@github-ui/conversations'
import type {DiffEntry} from '@github-ui/diff-lines'
import type {DiffUser} from '@github-ui/diff-lines/types'
import {getSelectedFullDiffHash, parsePathDigestWithoutLineNumbers} from '@github-ui/diff-lines/document-hash-helpers'
import {useUpdateUserDiffViewPreferenceMutation} from '@github-ui/diff-view-settings/hooks/mutations/use-update-user-diff-view-preference-mutation'
import {
  useDiffViewSettingsData,
  useSplitViewPreference,
  useWhitespacePreference,
} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'
import {CommentsPreference} from '@github-ui/diff-view-settings/types'
import {pullRequestContextLinesPath} from '@github-ui/paths'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useQueryClient} from '@github-ui/react-query'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {GlobalCommands} from '@github-ui/ui-commands'
import {useHideFooter} from '@github-ui/use-hide-footer'
import {Dialog, SplitPageLayout} from '@primer/react'
import {clsx} from 'clsx'
import {useCallback, useEffect, useMemo, useState} from 'react'
import {SlottedAppLayout} from '../AppLayout'
import {FileFilter, type FileFilterState} from '../components/diff-filtering/FileFilter'
import {PR_FILE_TREE_ID, PullRequestFileTree} from '../components/file-tree/PullRequestFileTree'
import treeStyles from '../components/file-tree/PullRequestFileTree.module.css'
import {PageLimitsBanner} from '../components/PageLimitsBanner'
import {PullRequestDiffsList} from '../components/PullRequestDiffsList'
import {PullRequestErrorState} from '../components/PullRequestErrorState'
import {LivePullRequestFilesToolbar} from '../components/toolbar/PullRequestFilesToolbar'
import {SelectedRefContextProvider} from '../contexts/SelectedRefContext'
import {useFileFiltering} from '../hooks/use-file-filtering'
import {useStitchSubjectIntoThreads} from '../hooks/use-stitch-subject-into-threads'
import {useCodeowners} from '../page-data/loaders/use-codeowners-data'
import {useDiffSummaries} from '../page-data/loaders/use-diff-summaries-data'
import {pullRequestMarkersKey} from '../page-data/loaders/use-markers-data'
import type {Codeowners} from '../page-data/payloads/codeowners'
import type {FilesRoutePayload} from '../page-data/payloads/files'
import {usePendingReviewPageData} from '../page-data/payloads/pending-review'
import styles from './Files.module.css'
import {useDiffEntries} from '../page-data/loaders/use-diff-entries'
import {useRouteHeaderData} from '../hooks/use-route-header-data'
import {ProgressiveDiffStoreProvider} from '../stores/ProgressiveDiffStore'

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
    codeowners,
    commits,
    diffSummaries: initialDiffSummaries,
    diffContents: initialDiffEntries,
    fileFilter,
    pullRequest,
    repository,
    threadPreviews,
    markers: initialMarkers,
    pageLimits,
    urls,
    user,
    viewerPendingReview,
  } = payload

  useStitchSubjectIntoThreads(initialMarkers, threadPreviews)

  const pendingReviewIDs = useMemo(() => {
    const pendingIDs = viewerPendingReview.comments.map(comment => parseInt(comment.threadId))
    return {id: viewerPendingReview.id, pendingReviewIDs: pendingIDs, comments: viewerPendingReview.comments}
  }, [viewerPendingReview.comments, viewerPendingReview.id])

  //i do not love this because we need some way to tell every diff that their comment submission needs to show as either
  //'add review comment' or 'start review', which requires us to subscribe to the pending comment set, which would
  //cause rerenders for every diff when a comment is added for the first time. There might not be a way around this
  //until we drill all of this logic way down into the diff line commenting components themselves
  const {data: pendingReviewCommentIDs} = usePendingReviewPageData({
    pathName: pullRequest.pathName,
    initialData: pendingReviewIDs,
  })

  const commentBatchPending = useMemo(() => {
    return (pendingReviewCommentIDs?.pendingReviewIDs.length ?? 0) > 0
  }, [pendingReviewCommentIDs?.pendingReviewIDs.length])

  useHideFooter(true)

  /*
   * Viewer settings
   */
  const viewSettingsData = useViewerSettings(user)

  const commentBoxConfig: CommentingImplementation['commentBoxConfig'] = useMemo(() => {
    return {
      emojiSkinTonePreference: user.commentingSettings.emojiSkinTonePreference,
      pasteUrlsAsPlainText: user.commentingSettings.pasteUrlsAsPlainText,
      useMonospaceFont: user.commentingSettings.useMonospaceFont,
    }
  }, [
    user.commentingSettings.emojiSkinTonePreference,
    user.commentingSettings.pasteUrlsAsPlainText,
    user.commentingSettings.useMonospaceFont,
  ])

  const {mutate: updateUserDiffViewPreference} = useUpdateUserDiffViewPreferenceMutation({
    onSuccess: () => {},
    onError: () => {},
  })
  const {data: settingsData} = useDiffViewSettingsData(viewSettingsData)
  const handleSwapDiffViewCommentCollapsePreference = useCallback(() => {
    updateUserDiffViewPreference({
      commentsPreference:
        settingsData?.commentsPreference === CommentsPreference.Visible
          ? CommentsPreference.Collapsed
          : CommentsPreference.Visible,
    })
  }, [settingsData?.commentsPreference, updateUserDiffViewPreference])

  const currentUser: DiffUser = useMemo(() => {
    return {
      avatarURL: user.currentUserAvatarUrl || '',
      login: user.currentUserLogin || '',
      tabSize: user.tabSize,
      splitPreference: settingsData?.splitPreference ?? 'unified',
      lineSpacing: settingsData?.lineSpacing ?? 'relaxed',
      canComment: user.canComment,
      canApplySuggestion: user.canApplySuggestion,
      commentsPreference: settingsData?.commentsPreference ?? 'visible',
      hasCopilotAccess: user.hasCopilotAccess,
    }
  }, [
    settingsData?.commentsPreference,
    settingsData?.lineSpacing,
    settingsData?.splitPreference,
    user.canApplySuggestion,
    user.canComment,
    user.currentUserAvatarUrl,
    user.currentUserLogin,
    user.hasCopilotAccess,
    user.tabSize,
  ])

  const {
    splitPagePaneHidden,
    splitPageContentHidden,
    isTreeExpanded,
    isMobileTreeExpanded,
    treeToggleElement,
    collapseTree,
  } = useTreePane(PR_FILE_TREE_ID, user.isFileTreeExpanded, currentUser, {
    size: 'small',
    mobileBreakpoint: 'lg',
  })

  /*
   * Diff and Filtering
   */

  // Codeowners data should be set in TSQ before filtering any diff summaries or diff entries,
  // because filtering is dependent on the codeowners data.
  const codeownersOptions: {basePath: string; initialData?: Codeowners} = {basePath: pullRequest.pathName}
  // Only set initialData if it exists
  if (codeowners) codeownersOptions.initialData = codeowners
  useCodeowners(codeownersOptions)

  const {data: diffSummaries} = useDiffSummaries(pullRequest.pathName, initialDiffSummaries)
  const initialFileFilterState: FileFilterState = {
    ...fileFilter.initialState,
    unselectedFileExtensions: new Set<string>(fileFilter.initialState.unselectedFileExtensions),
  }
  const [fileFilterState, setFileFilterState] = useState<FileFilterState>(initialFileFilterState)

  const [userHasInteracted, setUserHasInteracted] = useState(false)

  const [hiddenFilepathMap] = useFileFiltering(fileFilterState, pullRequest.pathName, userHasInteracted)

  useDiffEntries(pullRequest.pathName, initialDiffEntries as DiffEntry[])

  const filteredDiffEntries: DiffEntry[] = useMemo(() => {
    return initialDiffEntries
      .filter(diff => hiddenFilepathMap.get(diff.path) !== true)
      .map(diff => {
        return {
          ...diff,
          helpUrl: '',
          collapsed: diff.reviewed,
          commentingEnabled: true,
          changeType: diff.status,
          // pullRequest, // TODO might need to do some mapping here
        }
      })
  }, [initialDiffEntries, hiddenFilepathMap])

  // Loading the selected path digest that exist on page load to use in our ProgressiveDiffStore initial props
  const selectedPathDigest = () => parsePathDigestWithoutLineNumbers(getSelectedFullDiffHash())

  const filteredDiffSummaries = useMemo(() => {
    if (!diffSummaries) return []
    return diffSummaries.filter(summary => hiddenFilepathMap.get(summary.path) !== true)
  }, [diffSummaries, hiddenFilepathMap])

  const contextLinesURL = useMemo(() => {
    return pullRequestContextLinesPath({
      owner: repository.ownerLogin,
      repo: repository.name,
      number: pullRequest.number,
    })
  }, [repository.name, repository.ownerLogin, pullRequest.number])

  const queryClient = useQueryClient()

  useEffect(() => {
    queryClient.setQueryData(pullRequestMarkersKey(pullRequest.pathName), initialMarkers)
  }, [initialMarkers, pullRequest.pathName, queryClient])

  const commentBoxSubject = useMemo<RepoSubject>(() => {
    return {
      type: 'pull_request',
      id: {
        id: pullRequest.id,
      },
      pullRequestNumber: pullRequest.number,
      repository: {
        databaseId: repository.id,
        nwo: `${repository.ownerLogin}/${repository.name}`,
        slashCommandsEnabled: false, // TODO - follow up on this
      },
      comparison: {
        startCommitOid: pullRequest.comparison.baseOid,
        endCommitOid: pullRequest.comparison.headOid,
      },
    }
  }, [
    pullRequest.comparison.baseOid,
    pullRequest.comparison.headOid,
    pullRequest.id,
    pullRequest.number,
    repository.id,
    repository.name,
    repository.ownerLogin,
  ])

  const FilterFilterComponent = useMemo(() => {
    return (
      <FileFilter
        basePath={pullRequest.pathName}
        fileFilterMenuOptions={fileFilter.menuOptions}
        fileFilterState={fileFilterState}
        setFileFilterState={setFileFilterState}
        setUserHasInteracted={setUserHasInteracted}
        viewerLogin={currentUser.login}
        filterSize={!isTreeExpanded ? 'small' : 'medium'}
      />
    )
  }, [currentUser.login, fileFilter.menuOptions, fileFilterState, isTreeExpanded, pullRequest.pathName])

  const {aliveChannel, bannersData} = useRouteHeaderData()

  return (
    <SlottedAppLayout headerDivider="none" renderDefaultStickyHeader={false}>
      <ProgressiveDiffStoreProvider
        diffSummaries={filteredDiffSummaries}
        initialDiffEntries={filteredDiffEntries}
        selectedPathDigest={selectedPathDigest()}
        pathName={pullRequest.pathName}
      >
        <SelectedRefContextProvider
          baseRefOid={pullRequest.comparison.baseOid}
          path={ssrSafeWindow?.location?.pathname ?? ''}
        >
          <GlobalCommands
            commands={{
              'commit-diff-view:collapse-expand-comments': handleSwapDiffViewCommentCollapsePreference,
            }}
          />
          <LivePullRequestFilesToolbar
            bannersData={bannersData}
            urls={urls}
            user={user}
            aliveChannel={aliveChannel}
            diffEntries={filteredDiffEntries}
            commits={commits}
            commentBoxConfig={commentBoxConfig}
            commentBoxSubject={commentBoxSubject}
            currentUserLogin={user.currentUserLogin}
            fileFilter={FilterFilterComponent}
            isFileTreeExpanded={isTreeExpanded}
            lastReviewOid={user.lastReviewOid}
            pageLimits={pageLimits}
            pullRequest={pullRequest}
            repository={repository}
            shouldShowViewedFilesCount={user.shouldShowViewedFilesCount}
            // we are passing in the initial data for our useDiffSummaries call, so this will never be undefined
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            totalFilesCount={diffSummaries!.length}
            threadPreviews={threadPreviews}
            treeToggleElement={treeToggleElement}
            viewedFilesCount={user.viewedFilesCount}
          />
          {isMobileTreeExpanded && (
            <Dialog
              onClose={() => collapseTree()}
              position={{narrow: 'fullscreen', regular: 'left', wide: 'left'}}
              title={`Files`}
              className="p-0"
            >
              <PullRequestFileTree
                fileFilter={FilterFilterComponent}
                filteredDiffs={filteredDiffSummaries}
                onFileSelected={() => collapseTree()}
              />
            </Dialog>
          )}

          <SplitPageLayout.Pane
            position="start"
            sticky
            offsetHeader="60px"
            aria-label="File tree"
            padding="none"
            className={clsx(
              splitPagePaneHidden ? styles.HiddenPane : styles.Pane,
              isMobileTreeExpanded && styles.MobileExpanded,
              isTreeExpanded && styles.TreeExpanded,
            )}
            divider={{regular: 'line', narrow: 'none'}}
            widthStorageKey="diff-tree-pane-width"
            resizable
          >
            <PullRequestFileTree
              className={treeStyles['sidebar']}
              fileFilter={FilterFilterComponent}
              filteredDiffs={filteredDiffSummaries}
            />
          </SplitPageLayout.Pane>
          <SplitPageLayout.Content
            as="div"
            width="full"
            hidden={splitPageContentHidden}
            padding="none"
            className={clsx(styles.Content, isTreeExpanded && styles.TreeExpanded)}
          >
            <PageLimitsBanner pageLimits={pageLimits} repository={repository} urls={urls} />
            <PullRequestDiffsList
              basePath={pullRequest.pathName}
              commentBoxConfig={commentBoxConfig}
              commentBoxSubject={commentBoxSubject}
              contextLinesURL={contextLinesURL}
              currentUser={currentUser}
              headBranchName={pullRequest.headBranch}
              pullRequestState={pullRequest.state}
              filteredDiffSummaries={filteredDiffSummaries}
              repository={repository}
              commentBatchPending={commentBatchPending}
              endOfDiffsImagePath={urls.images ? urls.images['mona-hifive'] : undefined}
            />
          </SplitPageLayout.Content>
        </SelectedRefContextProvider>
      </ProgressiveDiffStoreProvider>
    </SlottedAppLayout>
  )
}

function useViewerSettings(user: FilesRoutePayload['user']) {
  const userSplitPreference = useSplitViewPreference(user.viewSettings.splitPreference)
  const userWhitespaceParam = useWhitespacePreference(user.viewSettings.hideWhitespace)
  return useMemo(() => {
    return {
      hideWhitespace: userWhitespaceParam,
      splitPreference: userSplitPreference,
      lineSpacing: user.viewSettings.lineSpacing,
      commentsPreference: user.viewSettings.commentsPreference,
    }
  }, [user.viewSettings.commentsPreference, user.viewSettings.lineSpacing, userSplitPreference, userWhitespaceParam])
}
