import type {DiffAnchor} from '@github-ui/diffs/types'
import {memo, type MouseEvent, type RefObject, useEffect, useMemo} from 'react'

import {DiffLineContextProvider} from '../contexts/DiffLineContext'
import type {
  ReplaceSelectedDiffRowRangeFromGridCellsFnArgs,
  UpdateSelectedDiffRowRangeFnArgs,
} from '../contexts/SelectedDiffRowRangeContext'
import {threadSummary} from '../helpers/conversation-helpers'
import DiffRowSelectedChecker from '../helpers/diff-row-selected-checker'
import {getDiffHunksData, getLineHunkData} from '../helpers/hunk-data-helpers'
import {isEmptyDiffLine, isDiffLine, rowIdFrom} from '../helpers/line-helpers'
import {useGridNavigation} from '../hooks/use-grid-navigation'
import type {DiffLine, ClientDiffLine, LineRange, FileDiffReference, DiffContext} from '../types'
import {EMPTY_DIFF_LINE} from '../types'
import {DiffLineSide} from './DiffLineTableRow'
import ExpandableHunkHeaderDiffLine from './ExpandableHunkHeaderDiffLine'
import {useDiffContext} from '../contexts/DiffContext'
import type {DiffMatchContent} from '../helpers/find-in-diff'
import {hasHiddenUnicodeCharacters, showHiddenUnicodeCharactersRaw} from '@github-ui/hidden-unicode-banner/utils'
import {showHiddenUnicodeCharactersHTML} from '@github-ui/hidden-unicode-banner/HiddenUnicodeCharacter'
import type {SafeHTMLString} from '@github-ui/safe-html'

/**
 * Split a context line into two lines, one for each side of the diff. The only divergence will be the annotations and
 * threads data, which will be filtered to only include threads and annotations on the right side.
 */
function splitContextLine(line: DiffLine): [DiffLine, DiffLine] {
  const leftLine: DiffLine = {
    ...line,
    threadsData: undefined,
    annotationsData: undefined,
  }
  const rightLine: DiffLine = {
    ...line,
    threadsData: line.threadsData
      ? {
          ...line.threadsData,
          threads: line.threadsData.threads,
          totalCommentsCount: line.threadsData.totalCommentsCount,
          totalCount: line.threadsData.totalCount,
        }
      : undefined,
  }
  return [leftLine, rightLine]
}

function groupDiffLines(lines: DiffLine[]): {
  leftLines: ClientDiffLine[]
  rightLines: ClientDiffLine[]
} {
  const leftLines: ClientDiffLine[] = []
  const rightLines: ClientDiffLine[] = []

  // Keep list of lines even, filling in blanks as needed
  const fillBlanks = () => {
    while (leftLines.length < rightLines.length) {
      leftLines.push(EMPTY_DIFF_LINE)
    }

    while (rightLines.length < leftLines.length) {
      rightLines.push(EMPTY_DIFF_LINE)
    }
  }

  for (const line of lines) {
    switch (line.type) {
      case 'ADDITION':
        rightLines.push(line)
        break
      case 'DELETION':
        leftLines.push(line)
        break
      case 'CONTEXT':
      case 'INJECTED_CONTEXT':
        fillBlanks()
        // eslint-disable-next-line no-case-declarations
        const [leftLine, rightLine] = splitContextLine(line)
        leftLines.push(leftLine)
        rightLines.push(rightLine)
        break
      case 'HUNK':
        fillBlanks()
        leftLines.push(line)
        rightLines.push(line)
    }
  }
  fillBlanks()

  return {leftLines, rightLines}
}

function useGroupedLines(diffLines: DiffLine[]) {
  const commentCount = diffLines.reduce((acc, line) => acc + (line.threadsData?.totalCount ?? 0), 0) ?? 0

  // This useMemo prevents async loaded comments from being injected into split diff lines if you're not using GQL
  // to get around this without losing memo, we check if the comment count has changed and use it as a dependency for the memo
  // eslint-disable-next-line react-hooks/react-compiler
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const {leftLines, rightLines} = useMemo(() => groupDiffLines(diffLines), [diffLines, commentCount])

  return {leftLines, rightLines}
}

const SplitDiffLines = memo(function SplitDiffLines({
  searchResults,
  diffContext = 'pr',
  focusedSearchResult,
  clearSelectedDiffRowRange,
  diffEntryId,
  diffHasHiddenUnicodeCharacters,
  diffLines,
  fileAnchor,
  fileLineCount,
  filePath,
  handleDiffRowClick,
  handleDiffSideCellSelectionBlocking,
  replaceSelectedDiffRowRangeFromGridCells,
  selectedDiffRowRange,
  setInGridMode,
  showHiddenUnicode,
  tableRef,
  updateDiffLines,
  updateSelectedDiffRowRange,
  copilotChatReference,
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
  fileAnchor: DiffAnchor
  fileLineCount: number
  filePath: string
  handleDiffRowClick: (
    event: MouseEvent<HTMLTableCellElement>,
    lineNumber: number,
    orientation: 'left' | 'right' | undefined,
    shiftKey: boolean,
    isNumberCell: boolean,
  ) => void
  handleDiffSideCellSelectionBlocking: (diffSide: 'left' | 'right') => void
  replaceSelectedDiffRowRangeFromGridCells: ReplaceSelectedDiffRowRangeFromGridCellsFnArgs
  selectedDiffRowRange: LineRange | null
  showHiddenUnicode: boolean
  tableRef: RefObject<HTMLTableElement>
  updateDiffLines: (diffAnchor: string, diffLines: DiffLine[]) => void
  updateSelectedDiffRowRange: UpdateSelectedDiffRowRangeFnArgs
  copilotChatReference?: FileDiffReference
  setInGridMode: (inGridMode: boolean) => void
  inGridMode: boolean
  firstLineNumberSelection: React.MutableRefObject<number | null>
}) {
  const {leftLines, rightLines} = useGroupedLines(diffLines)
  const {ghostUser} = useDiffContext()
  useGridNavigation({
    clearSelectedDiffRowRange,
    containerRef: tableRef,
    fileAnchor,
    isSplitDiff: true,
    leftLines,
    replaceSelectedDiffRowRangeFromGridCells,
    rightLines,
    selectedDiffRowRange,
    updateSelectedDiffRowRange,
    disabled: !inGridMode,
  })

  const diffRowSelectedChecker = useMemo(() => {
    if (!selectedDiffRowRange) return undefined
    return DiffRowSelectedChecker({
      selectedDiffRowRange,
      leftLines,
      rightLines,
      isNumberCell: true,
    })
  }, [selectedDiffRowRange, leftLines, rightLines])

  useEffect(() => {
    updateDiffLines(fileAnchor, diffLines)
  }, [diffLines, fileAnchor, updateDiffLines])

  const hunksData = useMemo(() => getDiffHunksData(leftLines), [leftLines])

  const leftLineWithSearchContentMap = new Map<number, DiffMatchContent[]>()
  const rightLineWithSearchContentMap = new Map<number, DiffMatchContent[]>()
  const hunkLinesWithSearchContentMap = new Map<number, DiffMatchContent[]>()
  for (let j = 0; j < (searchResults?.length ?? 0); j++) {
    const searchResult = searchResults?.[j]
    if (!searchResult) continue

    if (leftLineWithSearchContentMap.has(searchResult.leftLineNumber)) {
      leftLineWithSearchContentMap.get(searchResult.leftLineNumber)?.push(searchResult)
      //already had a match on this line, add to it
    } else if (searchResult.leftLineNumber !== -1) {
      leftLineWithSearchContentMap.set(searchResult.leftLineNumber, [searchResult])
    }

    if (hunkLinesWithSearchContentMap.has(searchResult.hunkLineNumber)) {
      hunkLinesWithSearchContentMap.get(searchResult.hunkLineNumber)?.push(searchResult)
    } else if (searchResult.isHunk) {
      hunkLinesWithSearchContentMap.set(searchResult.hunkLineNumber, [searchResult])
    }

    if (rightLineWithSearchContentMap.has(searchResult.rightLineNumber)) {
      rightLineWithSearchContentMap.get(searchResult.rightLineNumber)?.push(searchResult)
      //already had a match on this line, add to it
    } else if (searchResult.rightLineNumber !== -1) {
      rightLineWithSearchContentMap.set(searchResult.rightLineNumber, [searchResult])
    }
  }

  const processLineForHiddenUnicode = (line: ClientDiffLine): [ClientDiffLine, boolean] => {
    let hasHiddenUnicode = false
    if (diffHasHiddenUnicodeCharacters && !isEmptyDiffLine(line)) {
      hasHiddenUnicode = hasHiddenUnicodeCharacters(line.text)

      if (showHiddenUnicode && hasHiddenUnicode) {
        if (line.html) {
          line = {
            ...line,
            html: showHiddenUnicodeCharactersHTML(line.html as SafeHTMLString) ?? line.html,
          }
        } else {
          line = {...line, text: showHiddenUnicodeCharactersRaw(line.text)}
        }
      }
    }
    return [line, hasHiddenUnicode]
  }

  const lines: React.ReactNode[] = []
  for (let i = 0; i < leftLines.length; i++) {
    const leftLineBase = leftLines[i] as ClientDiffLine
    const rightLineBase = rightLines[i] as ClientDiffLine
    const prevLine = leftLines[i - 1]

    const [leftLine, leftLineHasHiddenUnicodeCharacters] = processLineForHiddenUnicode(leftLineBase)
    const [rightLine, rightLineHasHiddenUnicodeCharacters] = processLineForHiddenUnicode(rightLineBase)

    // Only need to use next right line when next left line is empty
    const nextLine = (isEmptyDiffLine(leftLines[i + 1]) ? rightLines[i + 1] : leftLines[i + 1]) as DiffLine | undefined
    const isHunkRow = isDiffLine(leftLine) && leftLine.type === 'HUNK'
    const rowId = rowIdFrom(fileAnchor, leftLine, rightLine)
    const currentLine = !isEmptyDiffLine(leftLine) ? leftLine : !isEmptyDiffLine(rightLine) ? rightLine : undefined

    if (!currentLine) continue

    const originalLineThreads = !isEmptyDiffLine(leftLine) ? leftLine.threadsData : undefined
    const modifiedLineThreads = !isEmptyDiffLine(rightLine) ? rightLine.threadsData : undefined

    const {currentHunk, nextHunk, previousHunk} = getLineHunkData(currentLine, hunksData)
    const leftResultsForLine = leftLineWithSearchContentMap.get(!isEmptyDiffLine(leftLine) ? leftLine.left ?? -2 : -2)
    const rightResultsForLine = rightLineWithSearchContentMap.get(
      !isEmptyDiffLine(rightLine) ? rightLine.right ?? -2 : -2,
    )
    const hunkResultsForLine = hunkLinesWithSearchContentMap.get(currentLine.blobLineNumber)
    const hunkFocusedResult =
      hunkResultsForLine?.[0]?.rightLineNumber === (rightLine as DiffLine)?.right ? focusedSearchResult : undefined
    const leftFocusedResult =
      leftResultsForLine?.[0]?.leftLineNumber === (leftLine as DiffLine)?.left ? focusedSearchResult : undefined
    const rightFocusedResult =
      rightResultsForLine?.[0]?.rightLineNumber === (rightLine as DiffLine)?.right ? focusedSearchResult : undefined

    const updatedLineThreads = threadSummary(modifiedLineThreads, ghostUser)
    const ogLineThreads = threadSummary(originalLineThreads, ghostUser)

    const diffLineContextData = {
      currentHunk,
      diffEntryId,
      fileAnchor,
      fileLineCount,
      filePath,
      isRowSelected:
        (diffRowSelectedChecker?.isRowSelected(leftLineBase) || diffRowSelectedChecker?.isRowSelected(rightLineBase)) ?? // Use original line here since it is a deep comparison
        false,
      nextHunk,
      previousHunk,
      rowId,
      isSplit: true,
      diffContext,
      setInGridMode,
    }

    lines.push(
      <tr key={rowId} className="diff-line-row">
        {isHunkRow ? (
          <DiffLineContextProvider
            {...{
              ...diffLineContextData,
              hasHiddenUnicodeCharacters: leftLineHasHiddenUnicodeCharacters || rightLineHasHiddenUnicodeCharacters,
              diffLine: currentLine,
            }}
            modifiedLineThreads={updatedLineThreads}
            originalLineThreads={ogLineThreads}
          >
            <ExpandableHunkHeaderDiffLine
              nextLine={nextLine}
              prevLine={prevLine as DiffLine}
              focusedSearchResult={hunkFocusedResult}
              resultsForLine={hunkResultsForLine}
            />
          </DiffLineContextProvider>
        ) : (
          <>
            <DiffLineContextProvider
              {...{
                ...diffLineContextData,
                diffLine: leftLine,
                hasHiddenUnicodeCharacters: leftLineHasHiddenUnicodeCharacters,
                isLeftSide: true,
              }}
              modifiedLineThreads={updatedLineThreads}
              originalLineThreads={ogLineThreads}
            >
              <DiffLineSide
                copilotChatReference={copilotChatReference}
                fileAnchor={fileAnchor}
                filePath={filePath}
                handleDiffRowClick={handleDiffRowClick}
                handleDiffSideCellSelectionBlocking={handleDiffSideCellSelectionBlocking}
                resultsForLine={leftResultsForLine}
                focusedSearchResult={leftFocusedResult}
                firstLineNumberSelection={firstLineNumberSelection}
              />
            </DiffLineContextProvider>
            <DiffLineContextProvider
              {...{
                ...diffLineContextData,
                diffLine: rightLine,
                hasHiddenUnicodeCharacters: rightLineHasHiddenUnicodeCharacters,
              }}
              modifiedLineThreads={updatedLineThreads}
              originalLineThreads={ogLineThreads}
            >
              <DiffLineSide
                copilotChatReference={copilotChatReference}
                fileAnchor={fileAnchor}
                filePath={filePath}
                handleDiffRowClick={handleDiffRowClick}
                handleDiffSideCellSelectionBlocking={handleDiffSideCellSelectionBlocking}
                resultsForLine={rightResultsForLine}
                focusedSearchResult={rightFocusedResult}
                firstLineNumberSelection={firstLineNumberSelection}
              />
            </DiffLineContextProvider>
          </>
        )}
      </tr>,
    )
  }

  return <>{lines}</>
})

export default SplitDiffLines
