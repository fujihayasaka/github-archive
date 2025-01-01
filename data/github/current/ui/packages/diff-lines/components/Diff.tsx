import {DiffFileHeader} from '@github-ui/diff-file-header'
import type React from 'react'
import {forwardRef, memo, useId, useMemo, useState} from 'react'
import type {DiffEntry, DiffUser, FileDiffReference} from '../types'
import type {CommentingImplementation, MarkerNavigationImplementation, Thread} from '@github-ui/conversations'
import {RichDiff} from './RichDiff'
import {DiffLines} from './DiffLines'
import styles from './Diff.module.css'
import {SubmoduleDiff} from './SubmoduleDiff'
import {useCopilotChatReference} from '../hooks/use-copilot-chat-reference'
import type {Repository} from '@github-ui/current-repository'
import {Blankslate} from '@primer/react/experimental'
import {AlertIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import {FileMarkers} from '@github-ui/conversations/file-markers'

/**
 * DiffProps extends the Diff data type by adding additional,
 * more UI-related properties.
 */
export interface DiffProps extends DiffEntry {
  focusedSearchResult?: number
  collapsed: boolean
  diffManuallyExpanded: boolean
  commentingImplementation?: CommentingImplementation | undefined
  fileComments: Thread[]
  initialExpandedThreadId?: string
  isSelected?: boolean
  markerNavigationImplementation?: MarkerNavigationImplementation | undefined
  rightSideContent: React.ReactNode | null
  leftSideContent: React.ReactNode | null
  onToggleCollapse: (event: React.MouseEvent, collapsed: boolean) => void
  currentUser: DiffUser
  repository: Pick<Repository, 'id' | 'name' | 'ownerLogin'>
  contextLinesURL: string
  basePath: string
}

export type PullRequestState = 'OPEN' | 'CLOSED' | 'QUEUED' | 'MERGED' | 'DRAFT'
export interface DiffContextProps extends DiffProps {
  canExpandOrCollapseLines: boolean
  hasExpandedAllRanges: boolean
  pullRequestState: PullRequestState
  addInjectedContextLines: (range: {start: number; end: number}) => void
  expandAllContextLines: () => void
  loadDiff: () => Promise<void>
  commentBatchPending: boolean
}

const DiffUnmemoized = forwardRef(function DiffUnmemoized(
  {
    collapsed,
    commentingEnabled,
    commentBatchPending,
    commentingImplementation,
    currentUser,
    diffContext,
    diffLines,
    diffManuallyExpanded,
    diffMatches,
    diffSize,
    focusedSearchResult,
    helpUrl,
    fileComments,
    isBinary,
    isSelected = false,
    isSubmodule,
    isTooBig,
    leftSideContent,
    linesAdded,
    linesChanged,
    linesDeleted,
    initialExpandedThreadId,
    markerNavigationImplementation,
    newTreeEntry,
    newCommitOid,
    objectId,
    oldTreeEntry,
    oldCommitOid,
    onToggleCollapse,
    path,
    pathDigest,
    pullRequestState,
    pullRequest,
    repository,
    richDiff,
    rightSideContent,
    hasExpandedAllRanges,
    expandAllContextLines,
    canExpandOrCollapseLines,
    status,
    submodule,
    truncatedReason,
    addInjectedContextLines,
    loadDiff,
  }: DiffContextProps,
  ref: React.Ref<HTMLDivElement>,
) {
  const [showRichDiff, setShowRichDiff] = useState(richDiff?.defaultToRichDiff)
  const showSubmodule = isSubmodule && !!submodule
  const showDiffLines = !showSubmodule && !showRichDiff
  const [linesManuallyUnhidden, setLinesManuallyUnhidden] = useState(diffManuallyExpanded)

  const copilotChatReference: FileDiffReference | undefined = useCopilotChatReference({
    isBinary,
    isSubmodule,
    path,
    status,
    repository,
    newCommitOid,
    newTreeEntry,
    oldCommitOid,
    oldTreeEntry,
    pathDigest,
    hasCopilotAccess: currentUser.hasCopilotAccess,
  })

  const onHandleLoadDiff = async () => {
    await loadDiff()

    setLinesManuallyUnhidden(true)
  }

  const viewerData = useMemo(() => {
    return {
      avatarUrl: currentUser?.avatarURL ?? '',
      diffViewPreference: currentUser?.splitPreference,
      isSiteAdmin: false,
      login: currentUser?.login ?? '',
      lineSpacingPreference: currentUser?.lineSpacing,
      tabSizePreference: currentUser?.tabSize ?? 8,
      viewerCanComment: currentUser?.canComment,
      viewerCanApplySuggestion: currentUser?.canApplySuggestion,
      commentsPreference: currentUser?.commentsPreference,
    }
  }, [currentUser])

  const id = useId()
  const headingId = `heading-${id}`

  return (
    <div
      role="region"
      ref={ref}
      aria-labelledby={headingId}
      id={`diff-${pathDigest}`}
      className={clsx(styles.diffTargetable, styles.diff)}
      data-targeted={isSelected}
      key={`${pathDigest}_${diffLines.length}`}
    >
      <div className={styles.diffHeaderWrapper}>
        <DiffFileHeader
          headingId={headingId}
          areLinesExpanded={hasExpandedAllRanges}
          canExpandOrCollapseLines={canExpandOrCollapseLines}
          fileLinkHref={`#diff-${pathDigest}`}
          isCollapsed={collapsed}
          isBinary={isBinary}
          size={diffSize}
          canToggleRichDiff={richDiff?.canToggleRichDiff}
          linesAdded={linesAdded}
          linesChanged={linesChanged}
          linesDeleted={linesDeleted}
          newMode={newTreeEntry?.mode}
          newPath={newTreeEntry?.path}
          oldMode={oldTreeEntry?.mode}
          oldPath={oldTreeEntry?.path}
          patchStatus={status}
          path={path}
          onToggleExpandAllLines={expandAllContextLines}
          onToggleFileCollapsed={event => onToggleCollapse(event, !collapsed)}
          onToggleDiffDisplay={rich => setShowRichDiff(rich)}
          additionalLeftSideContent={leftSideContent}
          rightSideContent={rightSideContent}
          showRichDiff={showRichDiff}
        />
      </div>
      {!collapsed ? (
        <div className="border position-relative rounded-bottom-2">
          {commentingImplementation && fileComments.length > 0 && (
            <FileMarkers
              batchPending={commentBatchPending}
              commentingImplementation={commentingImplementation}
              conversationListThreads={fileComments}
              filePath={path}
              repositoryId={repository.id.toString()}
              subject={{state: pullRequestState}}
              subjectId={pullRequest?.globalRelayId || ''}
            />
          )}
          {showSubmodule && <SubmoduleDiff submodule={submodule} />}

          {showRichDiff && (
            <RichDiff
              loading={false}
              proseDiffHtml={richDiff?.proseDiffHtml}
              fileRendererInfo={richDiff?.renderInfo}
              dependencyDiffPath={richDiff?.dependencyDiffPath}
            />
          )}

          {showDiffLines && (
            <DiffLines
              hasExpandedAllRanges={hasExpandedAllRanges}
              diffContext={diffContext}
              copilotChatReference={copilotChatReference}
              searchResults={diffMatches}
              focusedSearchResult={focusedSearchResult}
              diffEntryData={{
                diffLines,
                isBinary,
                isTooBig,
                linesChanged,
                newTreeEntry,
                newCommitOid,
                objectId,
                oldTreeEntry,
                oldCommitOid,
                path,
                pathDigest,
                status,
                truncatedReason,
              }}
              baseHelpUrl={helpUrl}
              commentBatchPending={commentBatchPending}
              repositoryId={repository.id.toString()}
              subject={{state: pullRequestState}}
              subjectId={pullRequest?.globalRelayId || ''}
              viewerData={viewerData}
              newCommitOid={newCommitOid}
              oldCommitOid={oldCommitOid}
              addInjectedContextLines={addInjectedContextLines}
              commentingEnabled={commentingEnabled || false}
              commentingImplementation={commentingImplementation}
              initialExpandedThreadId={initialExpandedThreadId}
              markerNavigationImplementation={markerNavigationImplementation}
              diffLinesManuallyUnhidden={linesManuallyUnhidden}
              onHandleLoadDiff={onHandleLoadDiff}
            />
          )}
        </div>
      ) : null}
    </div>
  )
})

type DiffErrorFallbackProps = Pick<
  DiffEntry,
  'path' | 'pathDigest' | 'linesAdded' | 'linesChanged' | 'linesDeleted' | 'status' | 'newTreeEntry' | 'oldTreeEntry'
>

export function DiffErrorFallback({
  path,
  pathDigest,
  linesAdded,
  linesChanged,
  linesDeleted,
  oldTreeEntry,
  newTreeEntry,
  status,
}: DiffErrorFallbackProps) {
  const id = useId()
  const headingId = `heading-${id}`

  const [isCollapsed, setIsCollapsed] = useState(false)

  return (
    <div
      role="region"
      aria-labelledby={headingId}
      id={`diff-${pathDigest}`}
      className={clsx(styles.diffTargetable, styles.diff)}
      key={`${pathDigest}_error`}
    >
      <div className={styles.diffHeaderWrapper}>
        <DiffFileHeader
          headingId={headingId}
          isCollapsed={isCollapsed}
          isBinary={false}
          linesAdded={linesAdded}
          linesChanged={linesChanged}
          linesDeleted={linesDeleted}
          newMode={newTreeEntry?.mode}
          newPath={newTreeEntry?.path}
          oldMode={oldTreeEntry?.mode}
          oldPath={oldTreeEntry?.path}
          patchStatus={status}
          path={path}
          onToggleFileCollapsed={() => setIsCollapsed(!isCollapsed)}
        />
      </div>
      {!isCollapsed && (
        <div className="border position-relative rounded-bottom-2">
          <Blankslate>
            <Blankslate.Visual>
              <AlertIcon size="medium" className="fgColor-muted" />
            </Blankslate.Visual>
            <Blankslate.Heading as="h4">There was an issue loading this file</Blankslate.Heading>
            <Blankslate.Description>
              {' '}
              Try refreshing the page or if the problem persists{' '}
              <a className="fgColor-muted" href="https://support.github.com/">
                <u>contact support</u>
              </a>
              .
            </Blankslate.Description>
          </Blankslate>
        </div>
      )}
    </div>
  )
}

/**
 * Represents a single file diff.
 *
 * @params DiffContextProps
 * @returns Diff
 */

export const Diff = memo(DiffUnmemoized)
