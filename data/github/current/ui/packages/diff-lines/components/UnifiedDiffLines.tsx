import {lineAnchorFrom, lineOrientationFrom} from '@github-ui/diffs/diff-line-helpers'
import type {DiffAnchor} from '@github-ui/diffs/types'
import {memo, type MouseEvent, type RefObject, useEffect, useMemo} from 'react'

import {DiffLineContextProvider} from '../contexts/DiffLineContext'
import type {
  UpdateSelectedDiffRowRangeFnArgs,
  ReplaceSelectedDiffRowRangeFromGridCellsFnArgs,
} from '../contexts/SelectedDiffRowRangeContext'
import DiffRowSelectedChecker from '../helpers/diff-row-selected-checker'
import {getDiffHunksData, getLineHunkData} from '../helpers/hunk-data-helpers'
import {rowIdFrom} from '../helpers/line-helpers'
import {useGridNavigation} from '../hooks/use-grid-navigation'
import type {DiffLine, LineRange, ClientDiffLine, FileDiffReference, DiffContext} from '../types'
import {CodeDiffLine} from './DiffLineTableRow'
import ExpandableHunkHeaderDiffLine from './ExpandableHunkHeaderDiffLine'
import type {DiffMatchContent} from '../helpers/find-in-diff'
import {hasHiddenUnicodeCharacters, showHiddenUnicodeCharactersRaw} from '@github-ui/hidden-unicode-banner/utils'
import {showHiddenUnicodeCharactersHTML} from '@github-ui/hidden-unicode-banner/HiddenUnicodeCharacter'
import type {SafeHTMLString} from '@github-ui/safe-html'

const UnifiedDiffLines = memo(function UnifiedDiffLines({
  searchResults,
  diffContext = 'pr',
  focusedSearchResult,
  clearSelectedDiffRowRange,
  diffEntryId,
  diffHasHiddenUnicodeCharacters,
  diffLines,
  fileLineCount,
  fileAnchor,
  filePath,
  tableRef,
  selectedDiffRowRange,
  showHiddenUnicode,
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
  diffHasHiddenUnicodeCharacters: boolean
  diffLines: DiffLine[]
  fileLineCount: number
  fileAnchor: DiffAnchor
  filePath: string
  tableRef: RefObject<HTMLTableElement>
  selectedDiffRowRange: LineRange | null
  showHiddenUnicode: boolean
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
    let currentLine = line
    const nextLine = diffLines[i + 1] as DiffLine | undefined
    const prevLine = diffLines[i - 1] as DiffLine | undefined
    const isHunkRow = line.type === 'HUNK'
    const lineAnchor = lineAnchorFrom(fileAnchor, lineOrientationFrom(currentLine.type), currentLine.blobLineNumber)
    const {currentHunk, nextHunk, previousHunk} = getLineHunkData(currentLine, hunksData)
    const resultsForLine = lineWithSearchContentMap.get(i)
    const focusedResult = i === resultsForLine?.[0]?.diffLineNumIndex ? focusedSearchResult : undefined

    const isRowSelected = diffRowSelectedChecker?.isRowSelected(line) ?? false // Use original line here since it is a deep comparison
    const rowId = rowIdFrom(fileAnchor, currentLine, currentLine)

    const lineHasHiddenUnicodeCharacters =
      diffHasHiddenUnicodeCharacters && hasHiddenUnicodeCharacters(currentLine.text)

    if (showHiddenUnicode && lineHasHiddenUnicodeCharacters) {
      if (currentLine.html) {
        currentLine = {
          ...currentLine,
          html: showHiddenUnicodeCharactersHTML(currentLine.html as SafeHTMLString) ?? currentLine.html,
        }
      } else {
        currentLine = {
          ...currentLine,
          text: showHiddenUnicodeCharactersRaw(currentLine.text),
        }
      }
    }

    const diffLineContextData = {
      diffEntryId,
      diffLine: currentLine,
      currentHunk,
      fileAnchor,
      fileLineCount,
      filePath,
      hasHiddenUnicodeCharacters: lineHasHiddenUnicodeCharacters,
      isLeftSide: currentLine.type === 'DELETION',
      isRowSelected,
      isSplit: false,
      nextHunk,
      previousHunk,
      diffContext,
      rowId,
      setInGridMode,
    }

    return (
      <tr key={rowId} className="diff-line-row">
        <DiffLineContextProvider {...diffLineContextData}>
          {isHunkRow ? (
            <ExpandableHunkHeaderDiffLine
              nextLine={nextLine}
              prevLine={prevLine}
              focusedSearchResult={focusedResult}
              resultsForLine={resultsForLine}
            />
          ) : (
            <CodeDiffLine
              filePath={filePath}
              copilotChatReference={copilotChatReference}
              handleDiffRowClick={handleDiffRowClick}
              firstLineNumberSelection={firstLineNumberSelection}
              lineAnchor={lineAnchor}
              resultsForLine={resultsForLine}
              focusedSearchResult={focusedResult}
            />
          )}
        </DiffLineContextProvider>
      </tr>
    )
  })

  return <>{lines}</>
})

export default UnifiedDiffLines
