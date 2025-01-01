import {
  fileCopiedOnly,
  fileModeChangedOnlyNoOtherChanges,
  fileRenamedOnly,
  fileTruncated,
  fileWasDeleted,
  fileWasGenerated,
  truncatedReason,
  whitespaceChangedOnly,
} from '@github-ui/diff-file-helpers'
import {SplitDiffTable, UnifiedDiffTable} from '@github-ui/diffs/DiffParts'
import {getLineNumberWidth} from '@github-ui/diffs/diff-line-helpers'
import type {DiffAnchor} from '@github-ui/diffs/types'
import {Link} from '@primer/react'
import type React from 'react'
import {memo, useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {
  SelectedDiffRowRangeContextProvider,
  useSelectedDiffRowRangeContext,
} from '../contexts/SelectedDiffRowRangeContext'
import {orderLineRange} from '../helpers/line-helpers'
import HiddenDiffPatch from './HiddenDiffPatch'
import {HunkHeaderData} from '../helpers/hunk-data-helpers'
import {SelectedDiffLinesOverlay} from './SelectedDiffLinesOverlay'
import SplitDiffLines from './SplitDiffLines'
import UnifiedDiffLines from './UnifiedDiffLines'
import type {CopilotChatFileDiffReferenceData, DiffContext, DiffEntryData, DiffLine} from '../types'
import type {DiffContextData} from '../contexts/DiffContext'
import {DiffContextProvider} from '../contexts/DiffContext'
import {overlayContainsEventTarget} from '../helpers/overlay-helpers'
import styles from './DiffLines.module.css'
import {clsx} from 'clsx'
import {ssrSafeDocument, ssrSafeWindow} from '@github-ui/ssr-utils'
import type {DiffMatchContent} from '../helpers/find-in-diff'
import {useSafeAsyncCallback} from '@github-ui/use-safe-async-callback'

function PlainTextStatus({diffAnchor, children}: React.PropsWithChildren<{diffAnchor: string}>) {
  return (
    <div className="fgColor-muted p-2" data-diff-anchor={diffAnchor}>
      {children}
    </div>
  )
}

export interface DiffLinesProps extends DiffContextData {
  searchResults?: DiffMatchContent[]
  diffContext?: DiffContext
  focusedSearchResult?: number
  baseHelpUrl: string
  diffEntryData: DiffEntryData
  diffLinesManuallyUnhidden: boolean
  onHandleLoadDiff: () => void
  copilotChatReferenceData?: CopilotChatFileDiffReferenceData
}

export const DiffLines = memo(function DiffLines({
  searchResults,
  diffContext = 'pr',
  focusedSearchResult,
  diffEntryData,
  diffLinesManuallyUnhidden,
  baseHelpUrl,
  onHandleLoadDiff,
  copilotChatReferenceData,
  ...diffContextData
}: DiffLinesProps) {
  const diffAnchor: DiffAnchor = `diff-${diffEntryData.pathDigest}`

  if (diffEntryData.isBinary) return <PlainTextStatus diffAnchor={diffAnchor}>Binary file not shown.</PlainTextStatus>
  if (fileRenamedOnly(diffEntryData))
    return <PlainTextStatus diffAnchor={diffAnchor}>File renamed without changes.</PlainTextStatus>
  if (fileCopiedOnly(diffEntryData))
    return <PlainTextStatus diffAnchor={diffAnchor}>File copied without changes.</PlainTextStatus>
  if (
    fileModeChangedOnlyNoOtherChanges(
      diffEntryData,
      diffEntryData.status,
      diffEntryData.oldTreeEntry?.mode,
      diffEntryData.newTreeEntry?.mode,
    )
  )
    return <PlainTextStatus diffAnchor={diffAnchor}>File mode changed.</PlainTextStatus>
  if (fileTruncated(diffEntryData))
    // Safe, because we just validated that field exists in the predicate above.
    return (
      <PlainTextStatus diffAnchor={diffAnchor}>
        {truncatedReason(diffEntryData.truncatedReason as string)}
      </PlainTextStatus>
    )
  if (whitespaceChangedOnly(diffEntryData))
    return <PlainTextStatus diffAnchor={diffAnchor}>Whitespace-only changes.</PlainTextStatus>
  if (!diffLinesManuallyUnhidden && fileWasDeleted(diffEntryData))
    return (
      <HiddenDiffPatch diffAnchor={diffAnchor} onLoadDiff={onHandleLoadDiff}>
        This file was deleted.
      </HiddenDiffPatch>
    )
  if (!diffLinesManuallyUnhidden && fileWasGenerated(diffEntryData)) {
    return (
      <HiddenDiffPatch
        diffAnchor={diffAnchor}
        helpText="customizing how changed files appear on GitHub."
        helpUrl={`${baseHelpUrl}/github/administering-a-repository/customizing-how-changed-files-appear-on-github`}
        onLoadDiff={onHandleLoadDiff}
      >
        Some generated files are not rendered by default. Learn more about{' '}
      </HiddenDiffPatch>
    )
  }

  if (diffEntryData.isTooBig) {
    // Currently for Commits, large diff entries are only fetched and rendered when the user manually expands the file.
    if (diffContext === 'commit' && diffEntryData.diffLines.length === 0) {
      if (diffLinesManuallyUnhidden) {
        return (
          <PlainTextStatus diffAnchor={diffAnchor}>
            Diff is too big to render. To view,{' '}
            <Link
              inline
              href={`${baseHelpUrl}/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/checking-out-pull-requests-locally`}
            >
              check out this pull request locally.
            </Link>
          </PlainTextStatus>
        )
      } else {
        return (
          <HiddenDiffPatch diffAnchor={diffAnchor} onLoadDiff={onHandleLoadDiff}>
            Large diffs are not rendered by default.
          </HiddenDiffPatch>
        )
      }
    }

    // Currently for PRX, large diff entries are always fetched upfront but not rendered until the user manually expands the file.
    // This will need to be updated to match the behavior of Commits in the near future.
    if (diffContext === 'pr') {
      if (diffEntryData.diffLines.length > 0) {
        return (
          <HiddenDiffPatch diffAnchor={diffAnchor} onLoadDiff={onHandleLoadDiff}>
            Large diffs are not rendered by default.
          </HiddenDiffPatch>
        )
      } else {
        return (
          <PlainTextStatus diffAnchor={diffAnchor}>
            Diff is too big to render. To view,{' '}
            <Link
              inline
              href={`${baseHelpUrl}/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/checking-out-pull-requests-locally`}
            >
              check out this pull request locally.
            </Link>
          </PlainTextStatus>
        )
      }
    }
  }

  if (!diffEntryData.diffLines) return null

  return (
    <DiffContextProvider {...diffContextData}>
      <SelectedDiffRowRangeContextProvider>
        <CodeDiffLines
          diffAnchor={diffAnchor}
          diffContext={diffContext}
          diffEntryData={diffEntryData}
          viewerData={diffContextData.viewerData}
          focusedSearchResult={focusedSearchResult}
          searchResults={searchResults}
          copilotChatReferenceData={copilotChatReferenceData}
        />
      </SelectedDiffRowRangeContextProvider>
    </DiffContextProvider>
  )
})

type CodeDiffLinesProps = Pick<
  DiffLinesProps,
  'diffEntryData' | 'diffContext' | 'viewerData' | 'searchResults' | 'focusedSearchResult' | 'copilotChatReferenceData'
> & {
  diffAnchor: DiffAnchor
}

function CodeDiffLines({
  diffAnchor,
  viewerData,
  diffEntryData,
  searchResults,
  focusedSearchResult,
  copilotChatReferenceData,
  diffContext,
}: CodeDiffLinesProps) {
  const tableRef = useRef<HTMLTableElement>(null)

  const [diffSideBeingBlocked, setDiffSideBeingBlocked] = useState<'left' | 'right' | null>(null)
  const fileLineCount = diffEntryData.newTreeEntry?.lineCount ?? diffEntryData.oldTreeEntry?.lineCount ?? 0

  const diffLines: DiffLine[] = useMemo(() => {
    const lastDiffLine = diffEntryData.diffLines[diffEntryData.diffLines.length - 1]

    // We need to append a client only hunk diffline type to allow for expanding the file
    // until EOF has been returned in diffEntryData.diffLines
    if (lastDiffLine?.blobLineNumber && lastDiffLine.blobLineNumber < fileLineCount) {
      return diffEntryData.diffLines.concat({
        __id: HunkHeaderData.finalLineId,
        blobLineNumber: lastDiffLine.blobLineNumber + 1,
        left: null,
        right: null,
        type: 'HUNK',
        html: '',
        text: '',
      } as DiffLine)
    }

    return diffEntryData.diffLines
  }, [diffEntryData.diffLines, fileLineCount])

  const {diffViewPreference, lineSpacingPreference, tabSizePreference} = viewerData
  const {
    selectedDiffRowRange,
    replaceSelectedDiffRowRange,
    replaceSelectedDiffRowRangeFromGridCells,
    clearSelectedDiffRowRange,
    updateDiffLines,
    updateSelectedDiffRowRange,
  } = useSelectedDiffRowRangeContext()

  const isSelectedFile = diffAnchor === selectedDiffRowRange?.diffAnchor

  useEffect(() => {
    // return undefined here to keep props stable
    if (!isSelectedFile) return

    const orderedSelectedDiffRowRange = orderLineRange(selectedDiffRowRange, diffLines)
    const selectedOrderHasNoChanges =
      !orderedSelectedDiffRowRange || orderedSelectedDiffRowRange === selectedDiffRowRange

    if (selectedOrderHasNoChanges) return

    replaceSelectedDiffRowRange(orderedSelectedDiffRowRange)
  }, [diffLines, selectedDiffRowRange, isSelectedFile, replaceSelectedDiffRowRange])

  //useLocation doesn't update when the URL updates from window.history.replaceState, so the old search was
  //never being updated if the URL wasn't being set with useNavigate
  const search = ssrSafeWindow?.location.search
  const isSplit = useMemo(() => {
    const searchParams = new URLSearchParams(search)
    const diffSearchParams = searchParams.get('diff')
    if (diffSearchParams === 'split') return true

    return diffViewPreference === 'split'
  }, [search, diffViewPreference])

  const lineNumberWidth = getLineNumberWidth(diffLines)

  const handleDiffSideCellSelectionBlocking = useCallback(
    (diffSide: 'left' | 'right') => {
      setDiffSideBeingBlocked(diffSide)
    },
    [setDiffSideBeingBlocked],
  )

  const diffLineFirstSelected = useRef<number | null>(null)

  const handleMouseUpOutside = useSafeAsyncCallback((e: MouseEvent) => {
    if (!e.target) return
    if (diffLineFirstSelected && !tableRef.current?.contains(e.target as Node)) {
      diffLineFirstSelected.current = null
    }
  })

  useEffect(() => {
    ssrSafeDocument?.addEventListener('mouseup', handleMouseUpOutside)

    return () => ssrSafeDocument?.removeEventListener('mouseup', handleMouseUpOutside)
  }, [handleMouseUpOutside])

  useEffect(() => {
    // ensure we don't leak the event listener on unmount
    return () => ssrSafeDocument?.removeEventListener('mousedown', handleMouseUpOutside)
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const handleDiffRowClick = useCallback(
    (
      event: React.MouseEvent<HTMLTableCellElement>,
      lineNumber: number,
      orientation: 'left' | 'right' | undefined,
      shiftKey: boolean,
      isNumberCell: boolean,
    ) => {
      // don't let clicks within any of the the overlays trigger this handler
      if (overlayContainsEventTarget(event.target as Node)) return
      if (event.defaultPrevented) return
      updateSelectedDiffRowRange(diffAnchor, lineNumber, orientation, shiftKey, isNumberCell)
    },
    [diffAnchor, updateSelectedDiffRowRange],
  )
  const diffLinesProps = {
    searchResults,
    diffContext,
    focusedSearchResult,
    clearSelectedDiffRowRange,
    diffEntryId: diffEntryData.objectId,
    diffLines,
    fileAnchor: diffAnchor,
    fileLineCount,
    filePath: diffEntryData.path,
    handleDiffRowClick,
    diffLineFirstSelected,
    handleDiffSideCellSelectionBlocking,
    replaceSelectedDiffRowRangeFromGridCells,
    selectedDiffRowRange: isSelectedFile ? selectedDiffRowRange : null,
    tableRef,
    updateDiffLines,
    updateSelectedDiffRowRange,
    copilotChatReferenceData,
  }

  return (
    <>
      <SelectedDiffLinesOverlay tableRef={tableRef} />
      <table
        ref={tableRef}
        className={clsx('tab-size', 'width-full', styles.tableLayoutFixed, {
          [styles.compact]: lineSpacingPreference === 'compact',
        })}
        data-block-diff-cell-selection={diffSideBeingBlocked}
        data-diff-anchor={diffAnchor}
        data-tab-size={tabSizePreference}
        data-paste-markdown-skip
        role="grid"
        style={
          {
            '--line-number-cell-width': `${lineNumberWidth}px`,
            '--line-number-cell-width-unified': `${parseFloat(lineNumberWidth) * 2}px`,
          } as React.CSSProperties
        }
      >
        {isSplit ? (
          <SplitDiffTable lineWidth={lineNumberWidth}>
            <SplitDiffLines {...diffLinesProps} />
          </SplitDiffTable>
        ) : (
          <UnifiedDiffTable lineWidth={lineNumberWidth}>
            <UnifiedDiffLines {...diffLinesProps} />
          </UnifiedDiffTable>
        )}
      </table>
    </>
  )
}
