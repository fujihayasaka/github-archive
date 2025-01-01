import {DiffFileHeader} from '@github-ui/diff-file-header'
import {memo, useEffect, useMemo, useRef, useState} from 'react'
import type {DiffEntry} from '../types'
import type {CommentingImplementation, MarkerNavigationImplementation} from '@github-ui/conversations'
import {fileRenamedOnly} from '@github-ui/diff-file-helpers'
import {RichDiff} from './RichDiff'
import {DiffLines} from './DiffLines'
import styles from './Diff.module.css'
import {SubmoduleDiff} from './SubmoduleDiff'

/**
 * DiffProps extends the Diff data type by adding additional,
 * more UI-related properties.
 */
export interface DiffProps extends DiffEntry {
  focusedSearchResult?: number
  collapsed: boolean
  diffManuallyExpanded: boolean
  commentingImplementation?: CommentingImplementation | undefined
  markerNavigationImplementation?: MarkerNavigationImplementation | undefined
  rightSideContent: React.ReactNode | null
  leftSideContent: React.ReactNode | null
  addInjectedContextLines: (range: {start: number; end: number}) => void
  onOptionCollapseToggle: (collapsed: boolean) => void
}

/**
 * Represents a single file diff.
 *
 * @params DiffProps
 * @returns Diff
 */

export const Diff = memo(DiffUnmemoized)

function DiffUnmemoized({
  addInjectedContextLines,
  collapsed,
  commentingEnabled,
  commentingImplementation,
  copilotChatReference,
  currentUser,
  diffContext,
  diffLines,
  diffManuallyExpanded,
  diffMatches,
  diffSize,
  focusedSearchResult,
  helpUrl,
  isBinary,
  isSubmodule,
  isTooBig,
  leftSideContent,
  linesAdded,
  linesChanged,
  linesDeleted,
  markerNavigationImplementation,
  newTreeEntry,
  newCommitOid,
  objectId,
  oldTreeEntry,
  oldCommitOid,
  onOptionCollapseToggle,
  path,
  pathDigest,
  pullRequest,
  repository,
  richDiff,
  rightSideContent,
  status,
  submodule,
  truncatedReason,
}: DiffProps) {
  const [showRichDiff, setShowRichDiff] = useState(richDiff?.defaultToRichDiff)
  const showSubmodule = isSubmodule && !!submodule
  const showDiffLines = !showSubmodule && !showRichDiff
  const [isCollapsed, setIsCollapsed] = useState(collapsed)
  const [linesManuallyUnhidden] = useState(diffManuallyExpanded)
  const hasExpandedAllRanges = useRef(false)

  const toggleCollapse = (event: React.MouseEvent) => {
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (event.altKey) {
      onOptionCollapseToggle(!isCollapsed)
    } else {
      collapsed = !isCollapsed
      setIsCollapsed(!isCollapsed)
    }
  }

  useEffect(() => {
    setIsCollapsed(collapsed)
  }, [collapsed])

  const canExpandOrCollapseLines = useMemo(() => {
    if (isBinary || isSubmodule) return false

    if (
      fileRenamedOnly({
        linesChanged,
        newTreeEntry,
        oldTreeEntry,
        status,
        truncatedReason,
      })
    )
      return false

    if (hasExpandedAllRanges.current) return true
    const firstDiffLineNumber = diffLines[1]?.blobLineNumber || 0

    if (firstDiffLineNumber > 1) return true

    const initialDiffLineCount = diffLines?.length || 0
    const lastDiffLineNumber = diffLines?.[initialDiffLineCount - 1]?.blobLineNumber || 0
    const fileLineCount = newTreeEntry?.lineCount || 0

    //- 1 on the diff line count because there is always the top hunk diff line no matter what
    if (lastDiffLineNumber < fileLineCount || initialDiffLineCount - 1 < fileLineCount) return true

    return false
  }, [diffLines, isBinary, isSubmodule, linesChanged, newTreeEntry, oldTreeEntry, status, truncatedReason])

  // TODO: Fill out this method or move it up into props.
  const expandAllContextLines = async () => {}
  const onHandleLoadDiff = async () => {}

  const viewerData = useMemo(() => {
    return {
      avatarUrl: currentUser?.avatarURL ?? '',
      diffViewPreference: currentUser?.splitPreference,
      isSiteAdmin: false,
      login: currentUser?.login ?? '',
      lineSpacingPreference: currentUser?.lineSpacing,
      tabSizePreference: currentUser?.tabSize ?? 8,
      viewerCanComment: currentUser?.canComment,
      viewerCanApplySuggestion: false,
      commentsPreference: currentUser?.commentsPreference,
    }
  }, [currentUser])

  return (
    <div className="position-relative" style={{contain: 'layout'}} key={`${pathDigest}_${diffLines.length}`}>
      <div className={styles.diffHeaderWrapper}>
        <DiffFileHeader
          areLinesExpanded={hasExpandedAllRanges.current}
          canExpandOrCollapseLines={canExpandOrCollapseLines}
          defaultToRichDiff={richDiff?.defaultToRichDiff}
          fileLinkHref={`#diff-${pathDigest}`}
          isCollapsed={isCollapsed}
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
          onToggleFileCollapsed={toggleCollapse}
          onToggleDiffDisplay={rich => setShowRichDiff(rich)}
          additionalLeftSideContent={leftSideContent}
          rightSideContent={rightSideContent}
        />
      </div>
      {!isCollapsed ? (
        <div className="border position-relative rounded-bottom-2">
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
              commentBatchPending={false}
              repositoryId={repository.id.toString()}
              subject={pullRequest?.subject || {}}
              subjectId={pullRequest?.globalRelayId || ''}
              viewerData={viewerData}
              newCommitOid={newCommitOid}
              oldCommitOid={oldCommitOid}
              addInjectedContextLines={addInjectedContextLines}
              commentingEnabled={commentingEnabled || false}
              commentingImplementation={commentingImplementation}
              markerNavigationImplementation={markerNavigationImplementation}
              diffLinesManuallyUnhidden={linesManuallyUnhidden}
              onHandleLoadDiff={onHandleLoadDiff}
            />
          )}
        </div>
      ) : null}
    </div>
  )
}
