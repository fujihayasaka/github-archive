import type {Subject} from '@github-ui/comment-box/subject'
import {ConversationMarkdownSubjectProvider} from '@github-ui/conversations'
import type {DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'
import {DiffFindOpenProvider} from '@github-ui/diff-lines'
import {
  useDiffViewSettingsData,
  useSplitViewPreference,
} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'
import {DiffPlaceholder} from '@github-ui/diffs/DiffParts'
import {commitContextLinesPath, commitPath} from '@github-ui/paths'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {GlobalCommands} from '@github-ui/ui-commands'
import {useClientValue} from '@github-ui/use-client-value'
import {useHideFooter} from '@github-ui/use-hide-footer'
import {SplitPageLayout} from '@primer/react'
import {useCallback, useEffect, useMemo, useState} from 'react'
import {RelayEnvironmentProvider} from 'react-relay'

import {CommitBanners} from '../components/Commit/banners/CommitBanners'
import {DiscussionComments} from '../components/Commit/comments/DiscussionComments'
import {CommitUnavailable} from '../components/Commit/CommitUnavailable'
import {Diffs} from '../components/Commit/Diffs'
import {DiffsHeader} from '../components/Commit/DiffsHeader'
import {DIFF_FILE_TREE_ID, FileTree, type PostSelectAction} from '../components/Commit/FileTree'
import {CommitHeader} from '../components/Commit/header/CommitHeader'
import {SSRDiffs} from '../components/Commit/SSRDiffs'
import {DiscussionCommentsProvider} from '../contexts/DiscussionCommentsContext'
import {InlineCommentsProvider} from '../contexts/InlineCommentsContext'
import {useDeferredCommentData} from '../hooks/use-fetch-deferred-comment-data'
import {useLoadBranchCommits} from '../hooks/use-load-branch-commits'
import {useTreePane} from '../shared/use-tree-pane'
import type {CommitPayload} from '../types/commit-types'
import {splitDiffEntryData} from '../utils/split-diff-entry-data'

const relayEnvironment = relayEnvironmentWithMissingFieldHandlerForNode()
const DIFF_CONTENT_PARENT_ID = 'diff-content-parent'

export function Commit() {
  useHideFooter(true)

  const payload = useRoutePayload<CommitPayload>()
  const {splitPagePaneHiddenSx, splitPageContentHidden, treeToggleElement, collapseTree, isMobileTreeExpanded} =
    useTreePane(DIFF_FILE_TREE_ID, payload.fileTreeExpanded)

  const [unselectedFileExtensions, setUnselectedFileExtensions] = useState(() => new Set<string>())
  const [isSSR] = useClientValue(() => false, true, [])
  const [filterTerm, setFilterTerm] = useState('')
  const [searchTerm, setSearchTerm] = useState('')
  //TODO: make this actually update properly, right now i just have the overlay appearing in a fixed spot
  // eslint-disable-next-line unused-imports/no-unused-vars
  const [isStickied, setIsStickied] = useState(false)

  const handleFileSelected = useCallback(
    (file: DiffDelta, postSelectAction?: PostSelectAction) => {
      if (postSelectAction === 'close_tree') {
        collapseTree()
      }
    },
    [collapseTree],
  )
  const commitInfo = useLoadBranchCommits(payload.commit.oid)
  const contextLinePathURL = commitContextLinesPath({
    owner: payload.repo.ownerLogin,
    repo: payload.repo.name,
    commitish: payload.commit.oid,
  })

  const handleFileExtensionsChange = useCallback(
    (type: 'selectFileExtension' | 'unselectFileExtension', extension: string) => {
      const unselectedExtensions = new Set(unselectedFileExtensions)

      if (type === 'selectFileExtension') {
        unselectedExtensions.delete(extension)
      } else if (type === 'unselectFileExtension') {
        unselectedExtensions.add(extension)
      }

      setUnselectedFileExtensions(unselectedExtensions)
    },
    [unselectedFileExtensions],
  )

  useEffect(() => {
    setUnselectedFileExtensions(new Set<string>())
  }, [payload.commit])

  const userSplitPreference = useSplitViewPreference(payload.splitViewPreference)
  const viewSettings = useMemo(() => {
    return {
      hideWhitespace: payload.ignoreWhitespace,
      splitPreference: userSplitPreference,
      lineSpacing: payload.diffLineSpacingPreference,
      commentsPreference: payload.commentsPreference,
    }
  }, [payload.commentsPreference, payload.diffLineSpacingPreference, payload.ignoreWhitespace, userSplitPreference])
  useDiffViewSettingsData(viewSettings)

  const repository = payload.repo
  const markdownSubject = useMemo<Subject>(
    () => ({
      repository: {
        databaseId: repository.id,
        nwo: `${repository.ownerLogin}/${repository.name}`,
        slashCommandsEnabled: false,
      },
      type: 'commit',
      id: {
        id: payload.commit.oid,
      },
    }),
    [repository.id, repository.name, repository.ownerLogin, payload.commit.oid],
  )

  //scroll to the top of the page on a soft nav
  useEffect(() => {
    if ((ssrSafeWindow?.scrollY ?? 0) > 0) {
      ssrSafeWindow?.scrollTo(0, 0)
    }
  }, [payload.path])

  // hook for fetching inline + discussion consolidated comment data
  const {deferredCommentData, state} = useDeferredCommentData(payload.repo, payload.commit.oid)
  const threadData = deferredCommentData?.threadMarkers
  const commentData = deferredCommentData?.inlineComments

  const [initialExpandedThreadId, setInitialExpandedThreadId] = useState<string | undefined>(undefined)

  useEffect(() => {
    if (state === 'loaded') {
      const hash = ssrSafeWindow?.location.hash.slice(1)
      if (!hash || !deferredCommentData) {
        return
      }

      // Discussion comments: #commitcomment-123
      if (/^commitcomment-\d+$/.test(hash)) {
        const foundDiscussionComment = deferredCommentData?.discussionComments.comments.find(
          comment => comment.urlFragment === hash,
        )

        if (foundDiscussionComment) {
          ssrSafeWindow?.requestAnimationFrame(() => {
            const commentElement = document.getElementById(hash ?? '')
            if (commentElement) {
              commentElement.scrollIntoView({block: 'center'})
              commentElement.focus()
            }
          })
        }
        // Inline comments: #r123
      } else if (/^r\d+$/.test(hash)) {
        const hashId = hash.replace('r', '')

        for (const threadMarker of deferredCommentData.threadMarkers) {
          if (!threadMarker.threads) {
            continue
          }

          // Technically there is only ever one thread in this array, but let's be safe and iterate over it
          for (const thread of threadMarker.threads) {
            if (!thread.commentsData.comments) {
              continue
            }

            for (const comment of thread.commentsData.comments) {
              if (comment && comment.id && comment.id.toString() === hashId) {
                setInitialExpandedThreadId(thread.id)
                return
              }
            }
          }
        }
      }
    }
  }, [deferredCommentData, state])

  if (payload.unavailableReason) {
    return (
      <CommitUnavailable
        commit={payload.commit}
        commitInfo={commitInfo}
        unavailableReason={payload.unavailableReason}
      />
    )
  }

  const [completeDiffData, fileTreeData] = splitDiffEntryData(payload.diffEntryData)

  const onCreatePermalink = () => {
    const permalink = commitPath({
      owner: payload.repo.ownerLogin,
      repo: payload.repo.name,
      commitish: payload.commit.oid,
    })
    window.history.pushState(null, document.title, permalink)
  }

  return (
    <RelayEnvironmentProvider environment={relayEnvironment}>
      <ConversationMarkdownSubjectProvider value={markdownSubject}>
        <InlineCommentsProvider
          initialInlineComments={commentData}
          initialFiles={threadData}
          initialExpandedThreadId={initialExpandedThreadId}
        >
          <GlobalCommands
            commands={{
              'commit-diff-view:create-permalink': onCreatePermalink,
            }}
          />
          <SplitPageLayout>
            <SplitPageLayout.Header>
              <CommitBanners commitBranchState={commitInfo} oid={payload.commit.oid} repo={payload.repo} />
              <CommitHeader commit={payload.commit} commitInfo={commitInfo} repo={payload.repo} />
            </SplitPageLayout.Header>
            <SplitPageLayout.Pane
              position="start"
              sticky
              sx={splitPagePaneHiddenSx}
              divider={{regular: 'line', narrow: 'none'}}
              widthStorageKey="diff-tree-pane-width"
              resizable
            >
              <ErrorBoundary fallback={<span>File tree failed to load.</span>}>
                <FileTree
                  contentId={DIFF_CONTENT_PARENT_ID}
                  diffs={fileTreeData}
                  onFileSelected={handleFileSelected}
                  unselectedFileExtensions={unselectedFileExtensions}
                  diffsHeader={<DiffsHeader treeToggleElement={treeToggleElement} headerInfo={payload.headerInfo} />}
                  onFileExtensionsChange={handleFileExtensionsChange}
                  onFilterTextChange={setFilterTerm}
                />
              </ErrorBoundary>
            </SplitPageLayout.Pane>
            <SplitPageLayout.Content
              as="div"
              width="full"
              hidden={splitPageContentHidden}
              padding="none"
              sx={{p: [3, 3, 3, 4], pt: [0, 0, 0, 0]}}
            >
              <div id={DIFF_CONTENT_PARENT_ID} tabIndex={-1}>
                {isSSR ? (
                  <SSRDiffs
                    diffEntryData={completeDiffData}
                    contextLinePathURL={contextLinePathURL}
                    repo={payload.repo}
                    oid={payload.commit.oid}
                    treeToggleElement={treeToggleElement}
                    headerInfo={payload.headerInfo}
                    totalFileCount={payload.diffEntryData?.length ?? 0}
                  />
                ) : (
                  <DiffFindOpenProvider searchTerm={searchTerm} setSearchTerm={setSearchTerm}>
                    <Diffs
                      totalFileCount={payload.diffEntryData?.length ?? 0}
                      treeToggleElement={treeToggleElement}
                      headerInfo={payload.headerInfo}
                      isTreeExpanded={isMobileTreeExpanded}
                      searchTerm={searchTerm}
                      setSearchTerm={setSearchTerm}
                      ignoreWhitespace={payload.ignoreWhitespace}
                      diffEntryData={completeDiffData}
                      contextLinePathURL={contextLinePathURL}
                      filterTerm={filterTerm}
                      unselectedFileExtensions={unselectedFileExtensions}
                      repo={payload.repo}
                      oid={payload.commit.oid}
                    />
                  </DiffFindOpenProvider>
                )}
                <DiscussionCommentsProvider
                  comments={deferredCommentData?.discussionComments?.comments}
                  commentCount={deferredCommentData?.discussionComments?.count}
                  canLoadMore={deferredCommentData?.discussionComments?.canLoadMore}
                  subscribed={deferredCommentData?.subscribed}
                  providerState={state}
                  repo={payload.repo}
                  commitOid={payload.commit.oid}
                >
                  <DiscussionComments commit={payload.commit} commentInfo={payload.commentInfo} />
                </DiscussionCommentsProvider>
                {/* DiffPlaceholder is used for the skeleton placeholder when a diff isn't loaded, it needs to be
            somewhere on the page so that it can be drawn from within the diff lines component.  */}
                <DiffPlaceholder />
              </div>
            </SplitPageLayout.Content>
          </SplitPageLayout>
        </InlineCommentsProvider>
      </ConversationMarkdownSubjectProvider>
    </RelayEnvironmentProvider>
  )
}
