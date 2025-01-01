import {lineAnchorFrom, lineOrientationFrom} from '@github-ui/diffs/diff-line-helpers'
import type {DiffAnchor} from '@github-ui/diffs/types'
import {Fragment, memo, type MouseEvent, type RefObject, useEffect, useMemo} from 'react'

import {DiffLineContextProvider} from '../contexts/DiffLineContext'
import type {
  UpdateSelectedDiffRowRangeFnArgs,
  ReplaceSelectedDiffRowRangeFromGridCellsFnArgs,
} from '../contexts/SelectedDiffRowRangeContext'
import DiffRowSelectedChecker from '../helpers/diff-row-selected-checker'
import {getDiffHunksData, getLineHunkData} from '../helpers/hunk-data-helpers'
import {isEmptyDiffLine, rowIdFrom} from '../helpers/line-helpers'
import {useGridNavigation} from '../hooks/use-grid-navigation'
import type {DiffLine, LineRange, ClientDiffLine, FileDiffReference, DiffContext} from '../types'
import {CodeDiffLine} from './DiffLineTableRow'
import ExpandableHunkHeaderDiffLine from './ExpandableHunkHeaderDiffLine'
import type {DiffMatchContent} from '../helpers/find-in-diff'
import {buildDiffLineScreenReaderSummary} from './DiffLineScreenReaderSummary'
import {ScopedCommands} from '@github-ui/ui-commands'
import {getExpandHunkFunctions} from '../hooks/use-expand-hunk'
import {useDiffContext} from '../contexts/DiffContext'

const UnifiedDiffLines = memo(function UnifiedDiffLines({
  searchResults,
  diffContext = 'pr',
  focusedSearchResult,
  clearSelectedDiffRowRange,
  diffEntryId,
  diffLines,
  fileLineCount,
  fileAnchor,
  filePath,
  tableRef,
  selectedDiffRowRange,
  handleDiffRowClick,
  updateDiffLines,
  updateSelectedDiffRowRange,
  replaceSelectedDiffRowRangeFromGridCells,
  copilotChatReference,
  setInGridMode,
  inGridMode,
  firstLineNumberSelection,
}: {
  searchResults?: DiffMatchContent[]
  diffContext?: DiffContext
  focusedSearchResult?: number
  clearSelectedDiffRowRange: () => void
  diffEntryId: string
  diffLines: DiffLine[]
  fileLineCount: number
  fileAnchor: DiffAnchor
  filePath: string
  tableRef: RefObject<HTMLTableElement>
  selectedDiffRowRange: LineRange | null
  handleDiffRowClick: (
    event: MouseEvent<HTMLTableCellElement>,
    lineNumber: number,
    orientation: 'left' | 'right' | undefined,
    shiftKey: boolean,
    isNumberCell: boolean,
  ) => void
  updateDiffLines: (diffAnchor: string, diffLines: DiffLine[]) => void
  updateSelectedDiffRowRange: UpdateSelectedDiffRowRangeFnArgs
  replaceSelectedDiffRowRangeFromGridCells: ReplaceSelectedDiffRowRangeFromGridCellsFnArgs
  copilotChatReference?: FileDiffReference
  setInGridMode: (inGridMode: boolean) => void
  inGridMode: boolean
  firstLineNumberSelection: React.MutableRefObject<number | null>
}) {
  useGridNavigation({
    clearSelectedDiffRowRange,
    containerRef: tableRef,
    fileAnchor,
    isSplitDiff: false,
    leftLines: diffLines as unknown as ClientDiffLine[],
    replaceSelectedDiffRowRangeFromGridCells,
    selectedDiffRowRange,
    updateSelectedDiffRowRange,
    disabled: !inGridMode,
  })

  const {addInjectedContextLines} = useDiffContext()

  const diffRowSelectedChecker = useMemo(() => {
    if (!selectedDiffRowRange) return undefined

    return DiffRowSelectedChecker({
      selectedDiffRowRange,
      leftLines: diffLines,
      isNumberCell: true,
    })
  }, [selectedDiffRowRange, diffLines])

  const hunksData = useMemo(() => getDiffHunksData(diffLines.map(diffLine => diffLine)), [diffLines])

  useEffect(() => {
    updateDiffLines(fileAnchor, diffLines)
  }, [diffLines, fileAnchor, updateDiffLines])

  const lineWithSearchContentMap = new Map<number, DiffMatchContent[]>()
  for (let i = 0; i < (searchResults?.length ?? 0); i++) {
    const searchResult = searchResults?.[i]

    if (!searchResult) continue
    if (searchResults && lineWithSearchContentMap.has(searchResult.diffLineNumIndex)) {
      lineWithSearchContentMap.get(searchResult.diffLineNumIndex)?.push(searchResult)
      //already had a match on this line, add to it
    } else if (searchResults) {
      lineWithSearchContentMap.set(searchResult.diffLineNumIndex, [searchResult])
    }
  }

  const lines = diffLines.map((line, i) => {
    const currentLine = line
    const nextLine = diffLines[i + 1] as DiffLine | undefined
    const prevLine = diffLines[i - 1] as DiffLine | undefined
    const isHunkRow = line.type === 'HUNK'
    const lineAnchor = lineAnchorFrom(fileAnchor, lineOrientationFrom(currentLine.type), currentLine.blobLineNumber)
    const {currentHunk, nextHunk, previousHunk} = getLineHunkData(currentLine, hunksData)
    const resultsForLine = lineWithSearchContentMap.get(i)
    const focusedResult = i === resultsForLine?.[0]?.diffLineNumIndex ? focusedSearchResult : undefined
    const summary = buildDiffLineScreenReaderSummary(line, line, 'RIGHT')

    const isRowSelected = diffRowSelectedChecker?.isRowSelected(currentLine) ?? false
    const rowId = rowIdFrom(fileAnchor, currentLine, currentLine)

    const diffLineContextData = {
      diffEntryId,
      diffLine: currentLine,
      currentHunk,
      fileAnchor,
      fileLineCount,
      filePath,
      isLeftSide: currentLine.type === 'DELETION',
      isRowSelected,
      isSplit: false,
      nextHunk,
      previousHunk,
      diffContext,
      rowId,
      setInGridMode,
    }

    const {expandEndOfHunk, expandEndOfPreviousHunk, expandStartOfHunk} = getExpandHunkFunctions(
      addInjectedContextLines,
      nextHunk,
      currentHunk,
      previousHunk,
    )

    const expandHunkDown = () => {
      // When a user is focused on a hunk row, "expanding down" means expanding the bottom of the
      // previous hunk that directly borders this row.
      if (!isEmptyDiffLine(line) && line?.type === 'HUNK') {
        expandEndOfPreviousHunk()
        return
      }
      expandEndOfHunk()
    }

    return (
      <Fragment
        // eslint-disable-next-line @eslint-react/no-array-index-key
        key={i}
      >
        <ScopedCommands
          as="tr"
          className="diff-line-row"
          commands={{
            'pull-requests-diff-view:expand-hunk-up': expandStartOfHunk,
            'pull-requests-diff-view:expand-hunk-down': expandHunkDown,
          }}
        >
          {' '}
          <DiffLineContextProvider {...diffLineContextData}>
            {isHunkRow ? (
              <ExpandableHunkHeaderDiffLine
                // eslint-disable-next-line @eslint-react/no-array-index-key
                key={i}
                nextLine={nextLine}
                prevLine={prevLine}
                focusedSearchResult={focusedResult}
                resultsForLine={resultsForLine}
              />
            ) : (
              <CodeDiffLine
                // eslint-disable-next-line @eslint-react/no-array-index-key
                key={i}
                filePath={filePath}
                copilotChatReference={copilotChatReference}
                handleDiffRowClick={handleDiffRowClick}
                firstLineNumberSelection={firstLineNumberSelection}
                lineAnchor={lineAnchor}
                resultsForLine={resultsForLine}
                focusedSearchResult={focusedResult}
                summary={summary}
              />
            )}
          </DiffLineContextProvider>
        </ScopedCommands>
      </Fragment>
    )
  })

  return <>{lines}</>
})

export default UnifiedDiffLines
