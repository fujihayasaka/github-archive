import type {CommentingImplementation} from '@github-ui/conversations'
import {fileRenamedOnly} from '@github-ui/diff-file-helpers'
import {Diff, parseCommentHash, type DiffProps} from '@github-ui/diff-lines'
import {removeUrlHash} from '@github-ui/history'
import {Suspense, useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {
  useDiffLinesIncludingContext,
  useFetchMoreContextLines,
  type ContextLineRange,
} from '../page-data/loaders/use-context-lines-data'
import {useMarkersDataWithSelectThreadAndAnnotationIDs} from '../page-data/loaders/use-markers-data'
import {
  useCollapsedDiffStatus,
  useUpdateAllCollapsedDiffStatus,
  useUpdateCollapsedDiffStatus,
} from '../hooks/use-collapsed-diff-status'
import {CodeownersBadge} from './CodeownersBadge'
import {BlobActionsMenu} from './BlobActionsMenu'
import {MarkAsViewedButton} from './MarkAsViewedButton'
import {usePullRequestCommenting} from '../hooks/use-pull-request-commenting'
import {findMarkersByPosition} from '../helpers/diff-helpers'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {useDiffSummary} from '../page-data/loaders/use-diff-summaries-data'
import {useExtractMarkerIds} from '../hooks/use-extract-marker-ids'
import {STICKY_HEADER_HEIGHT} from './toolbar/PullRequestFilesToolbar'
import type {PullRequestState} from '@github-ui/diff-lines/types'
import type {RepoSubject} from '@github-ui/comment-box/subject'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {PullRequestAppPayload} from '../page-data/payloads/pull-request-app'

export type PullRequestDiffProps = Omit<
  DiffProps,
  | 'leftSideContent'
  | 'rightSideContent'
  | 'onToggleCollapse'
  | 'commentingImplementation'
  | 'initialExpandedThreadId'
  | 'fileComments'
> & {
  headBranchName: string
  isSelected?: boolean
  commentBatchPending: boolean
  pullRequestState: PullRequestState
  commentBoxConfig: CommentingImplementation['commentBoxConfig']
  commentBoxSubject?: RepoSubject
}

// Access data store, maps threads into the difflines
export function PullRequestDiff({
  focusedSearchResult,
  basePath,
  diffManuallyExpanded,
  markerNavigationImplementation,
  headBranchName,
  contextLinesURL,
  diffLines,
  path,
  collapsed,
  commentBatchPending,
  commentBoxConfig,
  commentBoxSubject,
  isSelected = false,
  reviewed,
  ...diff
}: PullRequestDiffProps) {
  const {data: diffLinesWithContextLines} = useDiffLinesIncludingContext(basePath, path, diffLines)
  const {mutate: injectMoreContextLines, mutateAsync: injectMoreContextLinesAsync} = useFetchMoreContextLines(
    basePath,
    path,
  )
  const diffRef = useRef<HTMLDivElement>(null)
  const {helpUrl} = useAppPayload<PullRequestAppPayload>()

  const {data: isCollapsed} = useCollapsedDiffStatus(basePath, path, collapsed)
  const [initialExpandedThreadId, setInitialExpandedThreadId] = useState<string | undefined>(undefined)

  const {data: diffSummary} = useDiffSummary(basePath, path)
  const threadAndAnnotationIDs = useExtractMarkerIds(diffSummary)

  // due to how tanstack works, we need to destructure the data here to make sure we are only subscribed to
  // the data we need. This is due to the way the select funtion works
  const {data: markersData} = useMarkersDataWithSelectThreadAndAnnotationIDs({
    basePath,
    threadAndAnnotationIDs,
  })

  const diffLinesWithThreads = useMemo(() => {
    let tempDiffLinesWithThreads = diffLinesWithContextLines ?? []
    if (diffSummary && markersData) {
      tempDiffLinesWithThreads = tempDiffLinesWithThreads.map(diffLine => {
        // find marker by position and merge it into the diffLine
        return {
          ...diffLine,
          ...findMarkersByPosition(diffLine, diffSummary, markersData),
        }
      })
    }
    return tempDiffLinesWithThreads
  }, [diffLinesWithContextLines, markersData, diffSummary])

  const fileComments = useMemo(() => {
    if (!markersData || !markersData.threads) return []

    return Object.values(markersData.threads).filter(thread => thread && thread.subjectType?.toUpperCase() === 'FILE')
  }, [markersData])

  const hashChangeHandler = useCallback(() => {
    const hash = ssrSafeWindow?.location.hash
    if (hash && markersData && markersData.threads) {
      const parsedCommentId = parseCommentHash(hash)
      if (parsedCommentId) {
        for (const thread of Object.values(markersData.threads)) {
          if (thread) {
            for (const comment of thread.commentsData.comments) {
              if (comment.databaseId === parsedCommentId) {
                setInitialExpandedThreadId(thread.id)
                return
              }
            }
          }
        }
      }
    }

    // If we didn't find a matching thread, clear any previous state.
    setInitialExpandedThreadId(undefined)
  }, [markersData])

  const clearUrlHash = useCallback(() => {
    removeUrlHash()
    hashChangeHandler()
  }, [hashChangeHandler])

  useEffect(() => {
    hashChangeHandler() // Initialize on mount
    ssrSafeWindow?.addEventListener('hashchange', hashChangeHandler)

    return () => {
      ssrSafeWindow?.removeEventListener('hashchange', hashChangeHandler)
    }
  }, [hashChangeHandler])

  const commentingImplementation = usePullRequestCommenting(
    basePath,
    commentBoxConfig,
    diff.newCommitOid ?? '',
    commentBoxSubject,
  )

  const {mutate: changeCollapsedStatusForDiff} = useUpdateCollapsedDiffStatus()
  const {mutate: changeCollapsedStatusForAllDiffs} = useUpdateAllCollapsedDiffStatus(basePath)

  const onToggleCollapse = useCallback(
    (willCollapse: boolean, filePath: string, event?: React.MouseEvent) => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (event && event.altKey) {
        changeCollapsedStatusForAllDiffs({collapsedStatus: willCollapse, basePath})
      } else {
        changeCollapsedStatusForDiff({collapsedStatus: willCollapse, path: filePath, basePath})
        if (!willCollapse) return
        ssrSafeWindow?.requestAnimationFrame(() => {
          const rect = diffRef.current?.getBoundingClientRect()

          if (!rect) return

          // Only the top boundary is checked to ensure the element is not obscured by the sticky header or scrolled
          // out of view for when collapsed while sticky. We don't need to check the bottom because all we care about
          // is the diff header being visible
          const isOutOfView = rect.top < STICKY_HEADER_HEIGHT

          if (!isOutOfView) return
          ssrSafeWindow?.scrollTo({
            top: rect.top + ssrSafeWindow.scrollY - STICKY_HEADER_HEIGHT,
          })
        })
      }
    },
    [basePath, changeCollapsedStatusForAllDiffs, changeCollapsedStatusForDiff],
  )
  const expandedRangesArray = useRef<ContextLineRange[]>([])
  const [hasExpandedAllRanges, setHasExpandedAllRanges] = useState(false)

  const addInjectedContextLines = useCallback(
    async (range: ContextLineRange) => {
      // When the diff re-renders, we don't want to scroll to the targeted
      // line or comment as we would on the initial render.
      clearUrlHash()

      expandedRangesArray.current.push(range)
      injectMoreContextLines({
        contextLineRanges: expandedRangesArray.current,
        url: contextLinesURL,
        path,
      })
    },
    [injectMoreContextLines, contextLinesURL, path, clearUrlHash],
  )

  const loadDiff = useCallback(async () => {
    await injectMoreContextLinesAsync({
      contextLineRanges: [],
      url: contextLinesURL,
      path,
    })
  }, [injectMoreContextLinesAsync, contextLinesURL, path])

  const canExpandOrCollapseLines = useMemo(() => {
    if (diff.isBinary || diff.isSubmodule || diff.isTooBig) return false

    if (
      fileRenamedOnly({
        linesChanged: diff.linesChanged,
        newTreeEntry: diff.newTreeEntry,
        oldTreeEntry: diff.oldTreeEntry,
        status: diff.status,
        truncatedReason: diff.truncatedReason,
      })
    )
      return false

    if (hasExpandedAllRanges) return true
    if (diffLinesWithContextLines?.length === 0) return false
    const firstDiffLineNumber = diffLinesWithContextLines?.[1]?.blobLineNumber || 0

    if (firstDiffLineNumber > 1) return true

    const initialDiffLineCount = diffLinesWithContextLines?.length || 0
    const lastDiffLineNumber = diffLinesWithContextLines?.[initialDiffLineCount - 1]?.blobLineNumber || 0
    const fileLineCount = diff.newTreeEntry?.lineCount || 0

    //- 1 on the diff line count because there is always the top hunk diff line no matter what
    if (lastDiffLineNumber < fileLineCount || initialDiffLineCount - 1 < fileLineCount) return true

    return false
  }, [
    diff.isBinary,
    diff.isSubmodule,
    diff.isTooBig,
    diff.linesChanged,
    diff.newTreeEntry,
    diff.oldTreeEntry,
    diff.status,
    diff.truncatedReason,
    diffLinesWithContextLines,
    hasExpandedAllRanges,
  ])

  const expandAllContextLines = async () => {
    expandedRangesArray.current = []
    if (!hasExpandedAllRanges) {
      expandedRangesArray.current.push({
        start: 1,
        end: Math.max(diff.oldTreeEntry?.lineCount ?? 0, diff.newTreeEntry?.lineCount ?? 0),
      })
    }
    await injectMoreContextLinesAsync({
      contextLineRanges: expandedRangesArray.current,
      url: contextLinesURL,
      path,
    })
    setHasExpandedAllRanges(!hasExpandedAllRanges)
  }

  return (
    <Diff
      focusedSearchResult={focusedSearchResult}
      basePath={basePath}
      commentBatchPending={commentBatchPending}
      collapsed={isCollapsed ?? false}
      diffManuallyExpanded={diffManuallyExpanded}
      commentingImplementation={commentingImplementation}
      fileComments={fileComments}
      initialExpandedThreadId={initialExpandedThreadId}
      isSelected={isSelected}
      markerNavigationImplementation={markerNavigationImplementation}
      leftSideContent={
        <Suspense>
          <CodeownersBadge
            /* These classes need to match the flex ordering specified in DiffFileHeader,
      code badge currently looks strange on small screens.  */
            className="d-flex px-1 flex-items-center flex-order-2 flex-sm-order-1"
            diffPath={path}
            pullRequestBasePath={basePath}
            viewerLogin={diff.currentUser.login}
          />
        </Suspense>
      }
      rightSideContent={
        <div className="d-flex flex-items-center gap-2">
          {/* Hide file level comment button for staff ship: https://github.com/github/pull-requests/issues/17007 */}
          {/* <IconButton icon={CommentIcon} aria-label="Comment on this file" size="small" /> */}
          <MarkAsViewedButton
            path={path}
            basePath={basePath}
            setIsCollapsed={value => onToggleCollapse(value, path)}
            viewed={reviewed}
          />
          <BlobActionsMenu
            oid={diff.status === 'REMOVED' && diff.oldCommitOid ? diff.oldCommitOid : diff.newCommitOid || ''}
            path={path}
            repo={{
              name: diff.pullRequest?.headRepositoryName || diff.repository.name,
              ownerLogin: diff.pullRequest?.headRepositoryOwnerLogin || diff.repository.ownerLogin,
            }}
            isViewable={!diff.isSubmodule}
            branchName={headBranchName}
          />
        </div>
      }
      contextLinesURL={contextLinesURL}
      canExpandOrCollapseLines={canExpandOrCollapseLines}
      expandAllContextLines={expandAllContextLines}
      hasExpandedAllRanges={hasExpandedAllRanges}
      addInjectedContextLines={addInjectedContextLines}
      loadDiff={loadDiff}
      onToggleCollapse={(ev, value) => onToggleCollapse(value, path, ev)}
      path={path}
      ref={diffRef}
      {...diff}
      helpUrl={helpUrl}
      linesAdded={diffSummary?.linesAdded || diff.linesAdded || 0}
      linesChanged={diffSummary?.linesChanged || diff.linesChanged || 0}
      linesDeleted={diffSummary?.linesDeleted || diff.linesDeleted || 0}
      diffLines={diffLinesWithThreads}
    />
  )
}
