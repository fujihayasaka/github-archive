import {lineAnchorFrom, lineOrientationFrom} from '@github-ui/diffs/diff-line-helpers'
import type {DiffAnchor} from '@github-ui/diffs/types'
import type {MouseEvent, PropsWithChildren} from 'react'
import React, {useCallback, useRef} from 'react'
import {InlineCommentDialogModeProvider} from '@github-ui/conversations/inline-comment-dialog-mode-context'

import {ContentCell, EmptyCell, LineNumberCell} from './DiffLineTableCellParts'
import {MarkersDialogContextProvider} from '../contexts/MarkersDialogContext'
import {useDiffLineContext} from '../contexts/DiffLineContext'
import {isEmptyDiffLine} from '../helpers/line-helpers'
import type {FileDiffReference, DiffLine} from '../types'
import type {DiffMatchContent} from '../helpers/find-in-diff'
import {HiddenUnicodeAlert} from '@github-ui/hidden-unicode-banner/HiddenUnicodeAlert'

type HandleDiffRowClickFn = (
  event: React.MouseEvent<HTMLTableCellElement>,
  lineNumber: number,
  orientation: 'left' | 'right',
  shiftKey: boolean,
  isNumberCell: boolean,
) => void

const CodeDiffLineUnmemoized = ({
  resultsForLine,
  focusedSearchResult,
  handleDiffSideCellSelectionBlocking,
  handleDiffRowClick,
  lineAnchor,
  filePath,
  copilotChatReference,
  firstLineNumberSelection,
}: {
  resultsForLine?: DiffMatchContent[]
  focusedSearchResult?: number
  filePath: string
  lineAnchor: string
  handleDiffSideCellSelectionBlocking?: (diffSide: 'left' | 'right') => void
  handleDiffRowClick: HandleDiffRowClickFn
  copilotChatReference?: FileDiffReference
  firstLineNumberSelection: React.MutableRefObject<number | null>
}) => {
  const {diffLine, hasHiddenUnicodeCharacters, isLeftSide, isSplit, setInGridMode} = useDiffLineContext()
  const contentRef = useRef<HTMLTableCellElement>(null)
  const line = diffLine as DiffLine

  /*
   * display the left cell for all lines in a unified view, and left lines of a split view
   * this cell will not contain a number in the unified view if the line is an addition
   */
  const showLeftNumber = line.type !== 'ADDITION'
  const showLeftNumberCell = !isSplit || isLeftSide
  const displayingEmptyLeftNumberCell = showLeftNumberCell && !showLeftNumber

  /*
   * display the right cell for all lines in a unified view, and right lines of a split view
   * this cell will not contain a number in the unified view if the line is a deletion
   */
  const showRightNumber = line.type !== 'DELETION'
  const showRightNumberCell = !isSplit || !isLeftSide
  const displayingEmptyRightNumberCell = showRightNumberCell && !showRightNumber

  const handleLeftDiffNumberCellClick = useCallback(
    (event: MouseEvent<HTMLTableCellElement>) => {
      if (!line.left) return
      handleDiffRowClick(event, line.left, 'left', event.shiftKey, true)
    },
    [handleDiffRowClick, line.left],
  )

  const handleLeftDiffContentCellClick = useCallback(
    (event: MouseEvent<HTMLTableCellElement>) => {
      if (!line.left) return
      handleDiffRowClick(event, line.left, 'left', event.shiftKey, false)
    },
    [handleDiffRowClick, line.left],
  )

  const handleRightDiffNumberCellClick = useCallback(
    (event: MouseEvent<HTMLTableCellElement>) => {
      if (!line.right) return
      handleDiffRowClick(event, line.right, 'right', event.shiftKey, true)
    },
    [handleDiffRowClick, line.right],
  )

  const handleRightDiffContentCellClick = useCallback(
    (event: MouseEvent<HTMLTableCellElement>) => {
      if (!line.right) return
      handleDiffRowClick(event, line.right, 'right', event.shiftKey, false)
    },
    [handleDiffRowClick, line.right],
  )

  const handleRightDiffSideCellSelectionBlocking = useCallback(() => {
    if (!handleDiffSideCellSelectionBlocking) return
    const diffSideToBlock = 'left'
    handleDiffSideCellSelectionBlocking(diffSideToBlock)
  }, [handleDiffSideCellSelectionBlocking])

  const handleLeftDiffSideCellSelectionBlocking = useCallback(() => {
    if (!handleDiffSideCellSelectionBlocking) return
    const diffSideToBlock = 'right'
    handleDiffSideCellSelectionBlocking(diffSideToBlock)
  }, [handleDiffSideCellSelectionBlocking])

  return (
    <MarkersDialogContextProvider line={line}>
      {showLeftNumberCell && (
        <LineNumberCell
          copilotChatReference={copilotChatReference}
          columnIndex={0}
          filePath={filePath}
          // If this cell is empty, select the right-side (modified) row
          handleDiffCellClick={
            displayingEmptyLeftNumberCell ? handleRightDiffNumberCellClick : handleLeftDiffNumberCellClick
          }
          handleDiffSideCellSelectionBlocking={handleLeftDiffSideCellSelectionBlocking}
          firstLineNumberSelection={firstLineNumberSelection}
          contentRef={contentRef}
        >
          {hasHiddenUnicodeCharacters && !showRightNumber && (
            <DiffCodeAlert>
              <HiddenUnicodeAlert />
            </DiffCodeAlert>
          )}
          {showLeftNumber && line.left}
        </LineNumberCell>
      )}
      {showRightNumberCell && (
        <LineNumberCell
          copilotChatReference={copilotChatReference}
          columnIndex={isSplit ? 2 : 1}
          filePath={filePath}
          // If this cell is empty, select the left-side (original) row
          handleDiffCellClick={
            displayingEmptyRightNumberCell ? handleLeftDiffNumberCellClick : handleRightDiffNumberCellClick
          }
          handleDiffSideCellSelectionBlocking={handleRightDiffSideCellSelectionBlocking}
          firstLineNumberSelection={firstLineNumberSelection}
          contentRef={contentRef}
        >
          {hasHiddenUnicodeCharacters && showRightNumber && (
            <DiffCodeAlert>
              <HiddenUnicodeAlert />
            </DiffCodeAlert>
          )}
          {showRightNumber && line.right}
        </LineNumberCell>
      )}
      <InlineCommentDialogModeProvider enableDiffGridMode={setInGridMode}>
        <ContentCell
          copilotChatReference={copilotChatReference}
          columnIndex={isSplit ? (isLeftSide ? 1 : 3) : 2}
          filePath={filePath}
          handleDiffCellClick={isLeftSide ? handleLeftDiffContentCellClick : handleRightDiffContentCellClick}
          lineAnchor={lineAnchor}
          handleDiffSideCellSelectionBlocking={
            isLeftSide ? handleLeftDiffSideCellSelectionBlocking : handleRightDiffSideCellSelectionBlocking
          }
          searchResultsForLine={resultsForLine}
          focusedSearchResult={focusedSearchResult}
          firstLineNumberSelection={firstLineNumberSelection}
          ref={contentRef}
        />
      </InlineCommentDialogModeProvider>
    </MarkersDialogContextProvider>
  )
}

interface DiffSideProps {
  resultsForLine?: DiffMatchContent[]
  focusedSearchResult?: number
  fileAnchor: DiffAnchor
  filePath: string
  handleDiffRowClick: HandleDiffRowClickFn
  handleDiffSideCellSelectionBlocking: (diffSide: 'left' | 'right') => void
  copilotChatReference?: FileDiffReference
  firstLineNumberSelection: React.MutableRefObject<number | null>
}

export const DiffLineSideUnmemoized = ({
  resultsForLine,
  focusedSearchResult,
  fileAnchor,
  filePath,
  handleDiffRowClick,
  handleDiffSideCellSelectionBlocking,
  copilotChatReference,
  firstLineNumberSelection,
}: DiffSideProps) => {
  const {diffLine, isLeftSide} = useDiffLineContext()
  if (isEmptyDiffLine(diffLine)) {
    return (
      <>
        <EmptyCell columnIndex={isLeftSide ? 0 : 2} />
        <EmptyCell columnIndex={isLeftSide ? 1 : 3} showRightBorder={isLeftSide} />
      </>
    )
  }

  const lineOrientation = isLeftSide ? 'left' : lineOrientationFrom(diffLine.type)
  const lineNumber = lineOrientation === 'left' ? diffLine.left : diffLine.right
  const lineAnchor = lineAnchorFrom(fileAnchor, lineOrientation, lineNumber ?? 0)

  switch (diffLine.type) {
    case 'HUNK':
      return null
    case 'ADDITION':
    case 'DELETION':
    case 'CONTEXT':
    case 'INJECTED_CONTEXT':
      return (
        <CodeDiffLine
          copilotChatReference={copilotChatReference}
          filePath={filePath}
          handleDiffRowClick={handleDiffRowClick}
          handleDiffSideCellSelectionBlocking={handleDiffSideCellSelectionBlocking}
          lineAnchor={lineAnchor}
          resultsForLine={resultsForLine}
          focusedSearchResult={focusedSearchResult}
          firstLineNumberSelection={firstLineNumberSelection}
        />
      )
    default:
      throw new Error(`cannot handle type ${diffLine.type}`)
  }
}

function DiffCodeAlert({children}: PropsWithChildren) {
  return (
    <span className="position-absolute" style={{left: '-1px', zIndex: '1'}}>
      {children}
    </span>
  )
}

export const DiffLineSide = React.memo(DiffLineSideUnmemoized)
export const CodeDiffLine = React.memo(CodeDiffLineUnmemoized)
