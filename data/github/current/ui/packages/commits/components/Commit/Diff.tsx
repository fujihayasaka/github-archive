import type {Repository} from '@github-ui/current-repository'
import {useCurrentUser} from '@github-ui/current-user'
import {DiffFileHeader} from '@github-ui/diff-file-header'
import {fileRenamedOnly} from '@github-ui/diff-file-helpers'
import {type DiffLine, DiffLines, type DiffMatchContent, SubmoduleDiff, type Thread} from '@github-ui/diff-lines'
import {
  defaultViewSettings,
  useDiffViewSettingsData,
} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'
import React, {useCallback, useEffect, useId, useMemo, useRef, useState} from 'react'

import {type CommentThreadData, useInlineComments} from '../../contexts/InlineCommentsContext'
import {useCommentInfo} from '../../hooks/use-comment-info'
import {useCommenting} from '../../hooks/use-commenting'
import {useDiffInlineCommenting} from '../../hooks/use-diff-inline-commenting'
import {useDiffInlineMarkerNav} from '../../hooks/use-diff-inline-marker-nav'
import {
  type ContextLineRange,
  fetchDiffLines,
  fetchInjectedContextLines as getContextLines,
} from '../../hooks/use-diff-lines'
import type {CurrentUserExtended} from '../../shared/types'
import type {DiffEntryDataWithExtraInfo, ScrollToIndexOptions} from '../../types/commit-types'
import {mergeContextLines} from '../../utils/merge-context-lines'
import BlobActionsMenu from './BlobActionsMenu'
import {CommitRichDiff} from './CommitRichDiff'
import styles from './Diff.module.css'

const diffLineContextToAddCount = 40
const maxLinesOfFileToExpandFullDiff = 5000
const subject = {
  isInMergeQueue: false,
  state: 'OPEN', //???
}

interface DiffProps {
  diffMatches?: DiffMatchContent[]
  focusedSearchResult?: number
  diffEntryData: React.MutableRefObject<DiffEntryDataWithExtraInfo[]>
  contextLinePathURL: string
  recalcTotalHeightOfVirtualWindow: () => void
  onOptionCollapseToggle: (collapsed: boolean) => void
  index: number
  helpUrl: string
  headerStickyOffset?: number
  repo: Repository
  oid: string
  ignoreWhitespace: boolean
  virtualizerScrollTo?: (index: number, options?: ScrollToIndexOptions | undefined) => void
}

export const Diff = React.memo(DiffUnmemoized)

export function DiffUnmemoized({
  diffMatches,
  focusedSearchResult,
  diffEntryData,
  contextLinePathURL,
  recalcTotalHeightOfVirtualWindow,
  onOptionCollapseToggle,
  helpUrl,
  headerStickyOffset = 0,
  repo,
  oid,
  index,
  ignoreWhitespace,
  virtualizerScrollTo,
}: DiffProps) {
  const currentUser = useCurrentUser() as CurrentUserExtended | undefined
  let {data: diffViewSettings} = useDiffViewSettingsData()
  if (diffViewSettings === undefined) diffViewSettings = defaultViewSettings
  const markerNavigationImplementation = useDiffInlineMarkerNav()
  const commentInfo = useCommentInfo()
  const {
    getThreadDataByPathAndPosition,
    getInlineCommentInfoByPathAndPosition,
    updateInlineCommentMapWithNewComment,
    initialExpandedThreadId,
  } = useInlineComments()
  const {commentBoxConfig, commentBoxSubject} = useCommenting()
  const commentingImplementation = useDiffInlineCommenting(
    commentBoxConfig,
    commentBoxSubject,
    getInlineCommentInfoByPathAndPosition,
    updateInlineCommentMapWithNewComment,
  )

  // dont use lazy init on this state otherwise it doesn't map up comment data correctly
  const [diffEntryToUse, _setDiffEntryToUse] = useState(
    // eslint-disable-next-line @eslint-react/hooks-extra/prefer-use-state-lazy-initialization
    mapThreadDataIntoDiffEntry(diffEntryData.current[index]!, getThreadDataByPathAndPosition),
  )
  const setDiffEntryToUse = useCallback(
    (newDiffEntry: DiffEntryDataWithExtraInfo) => {
      _setDiffEntryToUse(mapThreadDataIntoDiffEntry(newDiffEntry, getThreadDataByPathAndPosition))
    },
    [getThreadDataByPathAndPosition],
  )

  const [isCollapsed, setIsCollapsed] = useState(diffEntryToUse.collapsed)
  const [showRichDiff, setShowRichDiff] = useState(diffEntryToUse.defaultToRichDiff)
  const showSubmodule = diffEntryToUse.isSubmodule && !!diffEntryToUse.submodule
  const showDiffLines = !showSubmodule && !showRichDiff

  const [linesManuallyUnhidden, setLinesManuallyUnhidden] = useState(diffEntryToUse.diffManuallyExpanded)
  const toggleCollapse = (event: React.MouseEvent) => {
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (event.altKey) {
      onOptionCollapseToggle(!isCollapsed)
    } else {
      diffEntryToUse.collapsed = !isCollapsed
      diffEntryData.current[index]!.collapsed = !isCollapsed
      setIsCollapsed(!isCollapsed)
    }
  }
  const hasExpandedAllRanges = useRef(false)

  useEffect(() => {
    setIsCollapsed(diffEntryToUse.collapsed)
  }, [diffEntryToUse.collapsed])
  const expandedRangesArray = useRef<ContextLineRange[]>([])

  const dealWithInjectedLines = useCallback(
    async (range: ContextLineRange) => {
      expandedRangesArray.current.push(range)
      const response = await getContextLines(expandedRangesArray.current, contextLinePathURL, diffEntryToUse.pathDigest)
      if (response !== undefined) {
        const prevDiffData = {...diffEntryToUse}
        prevDiffData.diffLines = mergeContextLines(prevDiffData.diffLines, response.diffEntryWithContext)
        setDiffEntryToUse(prevDiffData)
        diffEntryData.current[index] = prevDiffData
        recalcTotalHeightOfVirtualWindow()
      }
    },
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [contextLinePathURL, diffEntryData, diffEntryToUse, index],
  )

  const expandAllContextLines = async () => {
    expandedRangesArray.current = []
    if (!hasExpandedAllRanges.current) {
      if ((diffEntryToUse.newTreeEntry?.lineCount ?? 0) < maxLinesOfFileToExpandFullDiff) {
        //if file is small just expand the whole thing
        expandedRangesArray.current.push({
          start: 1,
          end: Math.max(diffEntryToUse.oldTreeEntry?.lineCount ?? 0, diffEntryToUse.newTreeEntry?.lineCount ?? 0),
        })
      } else {
        //if the file is large, only expand relevant context rather than the entire file
        expandedRangesArray.current = getRangesOutOfDiffLines(
          diffEntryToUse.diffLines,
          diffEntryToUse.newTreeEntry?.lineCount ?? 0,
        )
      }
    }
    hasExpandedAllRanges.current = !hasExpandedAllRanges.current
    const response = await getContextLines(expandedRangesArray.current, contextLinePathURL, diffEntryToUse.pathDigest)
    if (response !== undefined) {
      const prevDiffData = {...diffEntryToUse}
      prevDiffData.diffLines = mergeContextLines(prevDiffData.diffLines, response.diffEntryWithContext)
      setDiffEntryToUse(prevDiffData)
      diffEntryData.current[index] = prevDiffData
      recalcTotalHeightOfVirtualWindow()
    }
  }

  const onLoadDiff = useCallback(async () => {
    if (diffEntryToUse.diffLines.length === 0) {
      let diffLines
      try {
        diffLines = await fetchDiffLines({
          repo,
          sha1: diffEntryToUse.oldOid,
          sha2: diffEntryToUse.newOid,
          entry: diffEntryToUse.diffNumber.toString(),
        })
      } catch {
        throw new Error('Error fetching diff lines')
      }

      const prevDiffData = {...diffEntryToUse}
      prevDiffData.diffLines = diffLines
      setDiffEntryToUse(prevDiffData)
      diffEntryData.current[index] = prevDiffData
    }

    diffEntryToUse.diffManuallyExpanded = true
    diffEntryData.current[index]!.diffManuallyExpanded = true
    setLinesManuallyUnhidden(true)
    recalcTotalHeightOfVirtualWindow()
    requestAnimationFrame(() => {
      virtualizerScrollTo?.(index, {align: 'center'})
    })
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [diffEntryData, diffEntryToUse, index, recalcTotalHeightOfVirtualWindow])

  useEffect(() => {
    setDiffEntryToUse(diffEntryData.current[index]!)
    expandedRangesArray.current = []
  }, [ignoreWhitespace, index, diffEntryData, oid, repo.name, repo.ownerLogin, diffEntryToUse.path, setDiffEntryToUse])

  const canExpandOrCollapseLines = useMemo(() => {
    if (diffEntryToUse.isBinary) return false
    if (diffEntryToUse.isSubmodule) return false

    if (fileRenamedOnly(diffEntryToUse)) return false

    if (hasExpandedAllRanges.current) return true
    const firstDiffLineNumber = diffEntryData.current[index]?.diffLines?.[1]?.blobLineNumber || 0

    if (firstDiffLineNumber > 1) return true

    const initialDiffLineCount = diffEntryData.current[index]?.diffLines?.length || 0
    const lastDiffLineNumber = diffEntryData.current[index]?.diffLines?.[initialDiffLineCount - 1]?.blobLineNumber || 0
    const fileLineCount = diffEntryData.current[index]?.newTreeEntry?.lineCount || 0

    //- 1 on the diff line count because there is always the top hunk diff line no matter what
    if (lastDiffLineNumber < fileLineCount || initialDiffLineCount - 1 < fileLineCount) return true

    return false
  }, [
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    diffEntryData.current[index]?.diffLines,
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    diffEntryData.current[index]?.newTreeEntry?.lineCount,
    index,
    diffEntryData,
    diffEntryToUse,
  ])

  const viewerData = useMemo(() => {
    return {
      avatarUrl: currentUser?.avatarURL ?? '',
      diffViewPreference: diffViewSettings.splitPreference,
      isSiteAdmin: false,
      commentsPreference: diffViewSettings.commentsPreference,
      login: currentUser?.login ?? '',
      lineSpacingPreference: diffViewSettings.lineSpacing,
      tabSizePreference: currentUser?.tabSize ?? 8,
      viewerCanComment: commentInfo.canComment,
      viewerCanApplySuggestion: false,
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentUser?.avatarURL, currentUser, currentUser?.login, currentUser?.tabSize, diffViewSettings])

  const copilotDiffChatProps = useMemo(() => {
    if (!diffEntryToUse.copilotChatReference) {
      return undefined
    }

    return {
      copilotChatReference: diffEntryToUse.copilotChatReference,
    }
  }, [diffEntryToUse])

  const id = useId()
  const headingId = `heading-${id}`

  return (
    <div
      role="region"
      aria-labelledby={headingId}
      className="position-relative"
      style={{contain: 'layout'}}
      key={`${diffEntryToUse.pathDigest}_${diffEntryToUse.diffLines.length}`}
    >
      <div
        className={styles.diffHeaderWrapper}
        style={{
          '--header-sticky-offset': `${headerStickyOffset}px`,
        }}
      >
        <DiffFileHeader
          areLinesExpanded={hasExpandedAllRanges.current}
          canExpandOrCollapseLines={canExpandOrCollapseLines}
          fileLinkHref={`#diff-${diffEntryToUse.pathDigest}`}
          isCollapsed={isCollapsed}
          isBinary={diffEntryToUse.isBinary}
          isSubmodule={showSubmodule}
          headingId={headingId}
          size={diffEntryToUse.diffSize}
          canToggleRichDiff={diffEntryToUse.canToggleRichDiff}
          linesAdded={diffEntryToUse.linesAdded}
          linesChanged={diffEntryToUse.linesChanged}
          linesDeleted={diffEntryToUse.linesDeleted}
          newMode={diffEntryToUse.newTreeEntry?.mode}
          newPath={diffEntryToUse.newTreeEntry?.path}
          oldMode={diffEntryToUse.oldTreeEntry?.mode}
          oldPath={diffEntryToUse.oldTreeEntry?.path}
          patchStatus={diffEntryToUse.status}
          path={diffEntryToUse.path}
          onToggleExpandAllLines={expandAllContextLines}
          onToggleFileCollapsed={toggleCollapse}
          onToggleDiffDisplay={rich => setShowRichDiff(rich)}
          rightSideContent={
            <BlobActionsMenu
              oid={diffEntryToUse.status === 'REMOVED' && diffEntryToUse.deletedSha ? diffEntryToUse.deletedSha : oid}
              path={diffEntryToUse.path}
              repo={repo}
              isViewable={!diffEntryToUse.isSubmodule}
              copilotDiffChatProps={copilotDiffChatProps}
            />
          }
          showRichDiff={showRichDiff}
        />
      </div>
      {!isCollapsed ? (
        <div className="border position-relative rounded-bottom-2">
          {showSubmodule && diffEntryToUse.submodule && <SubmoduleDiff submodule={diffEntryToUse.submodule} />}

          {showRichDiff && (
            <CommitRichDiff
              commitOid={oid}
              path={diffEntryToUse.path}
              proseDiffHtml={diffEntryToUse.proseDifffHtml}
              fileRendererInfo={diffEntryToUse.renderInfo}
              dependencyDiffPath={diffEntryToUse.dependencyDiffPath}
            />
          )}

          {showDiffLines && (
            <DiffLines
              diffContext={'commit'}
              copilotChatReference={diffEntryToUse.copilotChatReference}
              searchResults={diffMatches}
              focusedSearchResult={focusedSearchResult}
              diffEntryData={diffEntryToUse}
              baseHelpUrl={helpUrl}
              commentingEnabled
              commentBatchPending={false}
              repositoryId={repo.id.toString()}
              //the subject and subjectID are PR specific things, but we can likely use them for our
              //commenting implementation as well
              subject={subject}
              subjectId={oid}
              viewerData={viewerData}
              newCommitOid={diffEntryToUse.newOid}
              oldCommitOid={diffEntryToUse.oldOid}
              addInjectedContextLines={dealWithInjectedLines}
              commentingImplementation={commentingImplementation}
              markerNavigationImplementation={markerNavigationImplementation}
              diffLinesManuallyUnhidden={linesManuallyUnhidden}
              onHandleLoadDiff={onLoadDiff}
              initialExpandedThreadId={initialExpandedThreadId}
            />
          )}
        </div>
      ) : null}
    </div>
  )
}

function getRangesOutOfDiffLines(currentLines: DiffLine[], fileLineCount: number) {
  const currentRanges = [] as ContextLineRange[]

  //the ranges can overlap and can also go higher than the number of lines in the file, which allows us to
  //severely simplify this logic without caring too much
  for (let i = 0; i < currentLines.length; i++) {
    const currentLine = currentLines[i]
    if (currentLine!.type === 'HUNK') {
      const previousLine = currentLines[i - 1 >= 0 ? i - 1 : 0]
      const nextLine = currentLines[i + 1 < currentLines.length ? i + 1 : currentLines.length - 1]
      const previousLineNumber = previousLine?.blobLineNumber
      const nextLineNumber = nextLine?.blobLineNumber
      if (previousLineNumber && nextLineNumber) {
        currentRanges.push({start: previousLineNumber, end: previousLineNumber + diffLineContextToAddCount})
        currentRanges.push({start: Math.max(nextLineNumber - diffLineContextToAddCount, 1), end: nextLineNumber})
      }
    }
  }
  const lastLineNumber = currentLines[currentLines.length - 1]!.blobLineNumber
  if (lastLineNumber < fileLineCount) {
    currentRanges.push({start: lastLineNumber, end: lastLineNumber + diffLineContextToAddCount})
  }
  return currentRanges
}

function mapThreadDataIntoDiffEntry(
  diffEntry: DiffEntryDataWithExtraInfo,
  threadDataFetcher: (path: string, position: number) => CommentThreadData | undefined,
) {
  for (const diffLine of diffEntry.diffLines ?? []) {
    const threadData = threadDataFetcher(diffEntry.path, diffLine.position!)

    if (!threadData) {
      diffLine.threadsData = undefined
    } else {
      diffLine.threadsData = {
        totalCommentsCount: threadData.count,
        totalCount: threadData.count,
        threads: (threadData.threads ?? []).map(thread => {
          const mapped: Thread = {
            id: thread.id,
            diffSide: thread.diffSide,
            commentsData: thread.commentsData,
            line: diffLine.blobLineNumber,
            isOutdated: false,
          }

          return mapped
        }),
      }
    }
  }

  return diffEntry
}
