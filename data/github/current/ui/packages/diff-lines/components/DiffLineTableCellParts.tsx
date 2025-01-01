import {Markers, StartConversation, usePersistedDiffCommentData} from '@github-ui/conversations'
import {InlineMarkers} from '@github-ui/conversations/inline-markers'
import type {DiffLineType} from '@github-ui/diffs/types'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {SafeHTMLDiv} from '@github-ui/safe-html'
import {ScopedCommands} from '@github-ui/ui-commands'
import {useSafeAsyncCallback} from '@github-ui/use-safe-async-callback'
import {CommentsPreference} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'
import {KebabHorizontalIcon, NoEntryIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import {useFocusTrap, ActionList, ActionMenu, useOnEscapePress} from '@primer/react'
import type React from 'react'
import type {ComponentPropsWithoutRef, FocusEvent, KeyboardEvent, ReactElement, ReactNode, RefObject} from 'react'
import {forwardRef, memo, useCallback, useEffect, useImperativeHandle, useMemo, useRef, useState} from 'react'

import {useDiffContext} from '../contexts/DiffContext'
import {useDiffLineContext} from '../contexts/DiffLineContext'
import {useMarkersDialogContext} from '../contexts/MarkersDialogContext'
import type {SelectedDiffLines} from '../contexts/SelectedDiffRowRangeContext'
import {useSelectedDiffRowRangeContext} from '../contexts/SelectedDiffRowRangeContext'
import {
  anchorLinkForSelection,
  calculateCommentIndicatorRightPositioning,
  calculateDiffLineCodeCellGutter,
  cellIdFrom,
  isContextDiffLine,
  isDiffLine,
  lineAcceptsComments,
  trimContentLine,
} from '../helpers/line-helpers'
import {useActionBarDialogs} from '../hooks/use-action-bar-dialogs'
import {useActionBarFocus} from '../hooks/use-action-bar-focus'
import {isGridNavigationKey} from '../hooks/use-grid-navigation'
import {useSuggestedChanges} from '../hooks/use-suggested-changes'
import type {ClientDiffLine, FileDiffReference, DiffLine} from '../types'
import {ActionBar} from './ActionBar'
import CommentIndicator from './CommentIndicator'
import {CellContextMenu, EmptyCellContextMenu} from './DiffLineTableCellContextMenus'
import type {PrunedIconButtonProps} from './ExpandableHunkHeaderDiffLine'
import {InProgressCommentIndicator} from './InProgressCommentIndicator'
import type {DiffMatchContent} from '../helpers/find-in-diff'
import {DiffHighlightedOverlay} from './DiffHighlightedOverlay'
import DiffLineScreenReaderSummary from './DiffLineScreenReaderSummary'
import {ssrSafeDocument} from '@github-ui/ssr-utils'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {useInlineCommentDialogModeContext} from '@github-ui/conversations/inline-comment-dialog-mode-context'
import {useSelectedDiffRowRangeContent} from '../hooks/use-selected-diff-row-range-content'
import {copyText} from '@github-ui/copy-to-clipboard'

const RIGHT_CLICK_BUTTON_CODE = 2

const DIMMED_LINE_NUMBER_TYPES: DiffLineType[] = ['CONTEXT', 'INJECTED_CONTEXT']

function useCellId(columnIndex: number) {
  const {rowId} = useDiffLineContext()
  if (!rowId) return undefined
  return cellIdFrom(rowId, columnIndex)
}

function useGridCellButtonProps(
  cellRef: RefObject<HTMLTableCellElement>,
): [cellProps: ComponentPropsWithoutRef<'td'>, buttonProps: ComponentPropsWithoutRef<'button'>] {
  const [isFocusWithin, setIsFocusWithin] = useState(false)
  const [isButtonFocused, setIsButtonFocused] = useState(false)

  // take the button out of the tab order when focus is outside of the cell
  // this means that it won't be tabbable until the grid cell is focused
  const buttonTabIndex = isFocusWithin ? 0 : -1

  const handleCellBlur = useCallback(
    (e: FocusEvent) => {
      // when the cell blurs, check if focus is transferring to a button within the cell
      if (cellRef.current && cellRef.current.contains(e.relatedTarget)) return
      setIsFocusWithin(false)
    },
    [cellRef],
  )

  const handleCellFocus = useCallback(() => {
    if (cellRef.current !== document.activeElement) return
    setIsFocusWithin(true)
  }, [cellRef])

  const handleButtonBlur = useCallback(
    (e: FocusEvent) => {
      if (cellRef.current && !cellRef.current.contains(e.relatedTarget)) {
        setIsFocusWithin(false)
      }

      setIsButtonFocused(false)
    },
    [cellRef],
  )
  const handleButtonFocusCapture = useCallback((e: FocusEvent) => {
    e.stopPropagation()
    setIsButtonFocused(true)
  }, [])

  const handleButtonKeydownCapture = useCallback((e: KeyboardEvent) => {
    // prevent focus zone from processing keystrokes on the button, since we want it to behave like it's not in the grid
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (isGridNavigationKey(e.key)) {
      e.stopPropagation()
    }
  }, [])

  // const baseCellProps = {onFocus: handleCellFocus, onBlur: handleCellBlur}
  // const cellProps = isButtonFocused ? {...baseCellProps, tabIndex: 0} : baseCellProps
  const cellProps = {onFocus: handleCellFocus, onBlur: handleCellBlur}

  const buttonProps = {
    // hide the button from the screen reader until it's focused to avoid polluting screen reader announcements
    'aria-hidden': !isButtonFocused,
    tabIndex: buttonTabIndex,
    onBlur: handleButtonBlur,
    // we use onFocusCapture instead of onFocus because we want to stop propagation before the focus zone
    // tries to handle the event.
    onFocusCapture: handleButtonFocusCapture,
    onKeyDownCapture: handleButtonKeydownCapture,
  }

  return [cellProps, buttonProps]
}

function useCommentDialogTitle(diffLine: DiffLine, isLeftSide: boolean) {
  const {selectedDiffRowRange} = useSelectedDiffRowRangeContext()
  return useMemo(() => {
    let text = 'Add a comment on'
    const isMultiLineComment: boolean =
      !!selectedDiffRowRange && selectedDiffRowRange.startLineNumber !== selectedDiffRowRange.endLineNumber

    if (selectedDiffRowRange && isMultiLineComment) {
      const lineSideIdentifier = {
        left: 'L',
        right: 'R',
      }
      const startSideIdentifier = lineSideIdentifier[selectedDiffRowRange.startOrientation]
      const endSideIdentifier = lineSideIdentifier[selectedDiffRowRange.endOrientation]
      const isMultiLineSelection = selectedDiffRowRange.startLineNumber !== selectedDiffRowRange.endLineNumber

      text += isMultiLineSelection
        ? ` lines ${startSideIdentifier}${selectedDiffRowRange.startLineNumber} to ${endSideIdentifier}${selectedDiffRowRange.endLineNumber}`
        : ` line ${startSideIdentifier}${selectedDiffRowRange.startLineNumber}`
    } else {
      const sideIdentifier = isLeftSide && !isContextDiffLine(diffLine) ? 'L' : 'R'
      text += ` line ${sideIdentifier}${diffLine.blobLineNumber}`
    }

    return text
  }, [diffLine, isLeftSide, selectedDiffRowRange])
}

function viewerCanCommentOnLine(
  commentingEnabled: boolean,
  viewerCanComment: boolean,
  diffLine: ClientDiffLine | undefined,
  selectedDiffLines: SelectedDiffLines,
) {
  return commentingEnabled && viewerCanComment && lineAcceptsComments(diffLine, selectedDiffLines)
}

type CellProps = Omit<ComponentPropsWithoutRef<'td'>, 'onKeyDown' | 'onCompositionStart' | 'onCompositionEnd'> & {
  columnIndex: number
  ContextMenu?: React.ReactElement
  lineAnchor?: string
  commentDialogOpen?: boolean
  handleDiffCellClick?: (event: React.MouseEvent<HTMLTableCellElement>) => void
  handleDiffSideCellSelectionBlocking?: (event: React.MouseEvent) => void
  handleHideMarkersFromFocus?: (state: boolean) => void
  startConversation?: () => void
  handleDiffCellMouseDown?: () => void
  enterDialogMode?: () => void
  firstLineNumberSelection?: React.MutableRefObject<number | null>
}

const Cell = forwardRef<HTMLTableCellElement, CellProps>(function Cell(
  {
    children,
    ContextMenu,
    className,
    columnIndex,
    handleDiffCellClick,
    handleDiffCellMouseDown,
    handleHideMarkersFromFocus,
    handleDiffSideCellSelectionBlocking,
    lineAnchor,
    firstLineNumberSelection,
    commentDialogOpen,
    startConversation,
    enterDialogMode,
    ...props
  }: CellProps,
  forwardedRef,
) {
  const {diffLine, fileAnchor, isRowSelected, isLeftSide, isSplit, setInGridMode} = useDiffLineContext()
  const line = diffLine as DiffLine
  const cellRef = useRef<HTMLTableCellElement>(null)

  // delegate the internal ref to the forwarded one if there is one
  useImperativeHandle<HTMLTableCellElement | null, HTMLTableCellElement | null>(forwardedRef, () => cellRef.current, [])

  const [showContextMenu, setShowContextMenu] = useState(false)
  const {selectedDiffRowRange} = useSelectedDiffRowRangeContext()
  const {disableInlineCommentDialogMode, isInDialogMode} = useInlineCommentDialogModeContext()
  const {getUnifiedDiffLineCode, getSplitDiffSingleLineCode, getSplitDiffMultiLineCode} =
    useSelectedDiffRowRangeContent(fileAnchor)
  const contextMenuOverlayRef = useRef<HTMLTableCellElement>(null)
  const handleClickOutside = useSafeAsyncCallback((e: MouseEvent) => {
    if (!e.target) return
    const eventTarget = e.target as Node
    if (
      showContextMenu &&
      !contextMenuOverlayRef.current?.contains(eventTarget) &&
      !cellRef.current?.contains(eventTarget) &&
      e.button === RIGHT_CLICK_BUTTON_CODE
    ) {
      // handle right-click outside of the menu and anchor cell
      setShowContextMenu(false)
    } else if (
      cellRef.current?.contains(eventTarget) &&
      (e.target as HTMLElement).closest('button')?.contains(eventTarget)
    ) {
      // handle click on button inside the anchor cell
      setShowContextMenu(false)
    }

    if (!cellRef.current?.contains(eventTarget)) {
      disableInlineCommentDialogMode()
      setInGridMode?.(true)
    }
  })

  useEffect(() => {
    ssrSafeDocument?.addEventListener('mousedown', handleClickOutside)
    return () => ssrSafeDocument?.removeEventListener('mousedown', handleClickOutside)
  }, [handleClickOutside])

  useEffect(() => {
    // ensure we don't leak the event listener on unmount
    return () => ssrSafeDocument?.removeEventListener('mousedown', handleClickOutside)

    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const copyCode = () => {
    const highlightedTextSelection = window.getSelection()

    // If user has selected text, through mousedown selection, we will prioritize copying that code in place of selectedDiffRowRangeContent.
    if (highlightedTextSelection && highlightedTextSelection.toString() !== '') {
      document.execCommand('copy')
      return
    }

    if (isSplit) {
      const isSingleCellSelection =
        selectedDiffRowRange === undefined ||
        (selectedDiffRowRange?.startOrientation === selectedDiffRowRange?.endOrientation &&
          selectedDiffRowRange?.startLineNumber === selectedDiffRowRange?.endLineNumber)

      // Copy split diff code
      if (isSingleCellSelection) {
        copyText(getSplitDiffSingleLineCode(isLeftSide ? 'left' : 'right', isLeftSide ? line?.left : line?.right))
      } else {
        copyText(getSplitDiffMultiLineCode(isLeftSide ? 'left' : 'right'))
      }

      return
    }

    // Copy unified diff code
    copyText(getUnifiedDiffLineCode())
  }

  const copyAnchorLink = () => {
    const link = anchorLinkForSelection({line, range: selectedDiffRowRange, fileAnchor})
    if (link) copyText(link)
  }

  const handleMouseUp = useCallback(() => {
    if (firstLineNumberSelection?.current) {
      firstLineNumberSelection.current = null
    }
  }, [firstLineNumberSelection])

  const handleMouseDown = useCallback(
    (event: React.MouseEvent) => {
      //only want to do mousedown handler if shift is not pressed
      const diffCellClicked = (event.target as HTMLElement)?.closest('td')
      const isNumberCell = diffCellClicked?.classList.contains('diff-line-number')
      // This will prevent unnecessary text highlighting when users are holding down shift key to select multiple lines with the mouse cursor.
      if (event.shiftKey) {
        event.preventDefault()
      } else {
        //we only want to update the selected diff row range if the click is on a number cell
        if (isNumberCell) {
          handleDiffCellMouseDown?.()
        } else if (firstLineNumberSelection) {
          firstLineNumberSelection.current = null
        }
      }
      if (firstLineNumberSelection && isNumberCell) {
        firstLineNumberSelection.current = isLeftSide ? line.left : line.right
      }
      handleDiffSideCellSelectionBlocking?.(event)
    },

    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [handleDiffSideCellSelectionBlocking],
  )

  useFocusTrap({
    restoreFocusOnCleanUp: true,
    containerRef: cellRef,
    disabled: !isInDialogMode,
  })

  const exitDialogMode = useCallback(() => {
    cellRef.current?.focus()
    disableInlineCommentDialogMode()
    setInGridMode?.(true)
  }, [disableInlineCommentDialogMode, setInGridMode])

  const {diff_inline_comments: diffInlineCommentsFeatureIsEnabled} = useFeatureFlags()

  const handleOnKeyPress = useCallback(
    (e: React.KeyboardEvent<HTMLTableCellElement>) => {
      if (!diffInlineCommentsFeatureIsEnabled) return

      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (e.target === cellRef.current && e.key === 'Enter') enterDialogMode?.()
    },
    [enterDialogMode, diffInlineCommentsFeatureIsEnabled],
  )

  useOnEscapePress(() => {
    exitDialogMode()
  }, [exitDialogMode])

  return (
    <ScopedCommands
      as="td"
      commands={{
        'pull-requests-diff-view:copy-code': copyCode,
        'pull-requests-diff-view:copy-anchor-link': copyAnchorLink,
        'pull-requests-diff-view:start-conversation-current': startConversation,
      }}
      ref={cellRef}
      data-grid-cell-id={useCellId(columnIndex)}
      data-line-anchor={lineAnchor}
      data-selected={isRowSelected}
      role={!isInDialogMode ? 'gridcell' : 'dialog'}
      style={{userSelect: 'none', position: 'relative'}}
      tabIndex={-1}
      valign="top"
      className={
        className ? `focusable-grid-cell ${className} ${columnIndex < 3 ? 'left-side' : ''}` : 'focusable-grid-cell'
      }
      onKeyUp={handleOnKeyPress}
      onBlur={e => (e.target.ariaSelected = 'false')}
      onClick={handleDiffCellClick}
      onFocus={e => (e.target.ariaSelected = 'true')}
      onMouseDown={handleMouseDown}
      onMouseUp={handleMouseUp}
      title={!isInDialogMode ? '' : 'Title'}
      {...props}
    >
      {children}
      {/* Only render the context menu when it's visible, because Overlay performs calculations that become expensive
          when every cell is rendering an overlay */}
      {ContextMenu && showContextMenu && (
        <ActionMenu anchorRef={cellRef} open onOpenChange={setShowContextMenu}>
          <ActionMenu.Overlay width={children ? 'medium' : 'small'}>
            <ActionList>{ContextMenu}</ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      )}
    </ScopedCommands>
  )
})

export function HunkKebabIcon() {
  const {isSplit} = useDiffLineContext()

  return (
    <div className={clsx('hunk-kebab-icon pr-2 pb-1', !isSplit && 'hunk-kebab-icon-unified')}>
      <KebabHorizontalIcon />
    </div>
  )
}

interface ContentCellProps extends React.ComponentProps<'td'> {
  summary?: string
  searchResultsForLine?: DiffMatchContent[]
  focusedSearchResult?: number
  columnIndex: number
  lineAnchor?: string
  firstLineNumberSelection: React.MutableRefObject<number | null>
  handleDiffCellClick: (event: React.MouseEvent<HTMLTableCellElement>) => void
  handleDiffSideCellSelectionBlocking: (event: React.MouseEvent) => void
  filePath: string
  copilotChatReference?: FileDiffReference
  commentIndicator?: JSX.Element | null
}

/**
 * Renders the diff text.
 * Optionally renders comment indicator and action menu, if commenting is enabled.
 */

export const ContentCell = memo(ContentCellUnmemoized)
function ContentCellUnmemoized({
  summary,
  searchResultsForLine,
  focusedSearchResult,
  columnIndex,
  lineAnchor,
  firstLineNumberSelection,
  handleDiffCellClick,
  handleDiffSideCellSelectionBlocking,
  filePath,
  copilotChatReference,
}: ContentCellProps) {
  const {diffLine, fileAnchor, isLeftSide, setInGridMode} = useDiffLineContext()
  const line = diffLine as DiffLine
  const [lineHtml, trimmedChar] = trimContentLine(line.html, line.type)
  const [manuallyUpdateCommentsWithThisThreadId, setManuallyUpdateComments] = useState('')
  const showTrimmedChar = trimmedChar && ['+', '-'].includes(trimmedChar)
  const {isActionBarVisible} = useMarkersDialogContext()
  const {selectedDiffRowRange, selectedDiffLines} = useSelectedDiffRowRangeContext()
  const {
    commentBatchPending,
    commentingEnabled,
    commentingImplementation,
    initialExpandedThreadId,
    markerNavigationImplementation,
    repositoryId,
    subjectId,
    subject,
    viewerData,
  } = useDiffContext()
  const {hasPersistedComment} = usePersistedDiffCommentData({
    diffSide: isLeftSide ? 'LEFT' : 'RIGHT',
    filePath,
    line: line.blobLineNumber,
    subjectId,
    fileLevelComment: false,
  })

  const {isInDialogMode, enableInlineCommentDialogMode, disableInlineCommentDialogMode} =
    useInlineCommentDialogModeContext()

  const showStartConversation: boolean = useMemo(() => {
    return viewerCanCommentOnLine(commentingEnabled, viewerData.viewerCanComment, line, selectedDiffLines)
  }, [commentingEnabled, viewerData, line, selectedDiffLines])

  // When a user closes a dialog launched from either the action bar or the context menu, we want to return focus to the
  // element that triggered the dialog.
  const actionBarReturnFocusRef = useRef<HTMLButtonElement | null>(null)
  const cellRef = useRef<HTMLTableCellElement>(null)
  const {diff_inline_comments: diffInlineCommentsFeatureIsEnabled} = useFeatureFlags()

  const commentIndicatorRightPositioning = calculateCommentIndicatorRightPositioning({
    shouldAlignRight: hasPersistedComment || !showStartConversation,
    lineSpacingPreference: viewerData.lineSpacingPreference,
  })
  const hasThreads = !!line.threadsData?.threads?.length || !!line.annotationsData?.annotations?.length
  const commentIndicatorGutterSize = calculateDiffLineCodeCellGutter({
    hasThreads: hasThreads && !diffInlineCommentsFeatureIsEnabled,
  })

  const addCommentDialogTitle = useCommentDialogTitle(line, !!isLeftSide)

  const cellId = useCellId(columnIndex)
  const {handleCellBlur, handleCellFocus, handleCellMouseEnter, handleCellMouseLeave} = useActionBarFocus({
    cellRef,
  })

  const [shouldShowLineThreads, setShouldShowLineThreads] = useState(false)
  const toggleShowingInlineThreads = useCallback(() => {
    if (!shouldShowLineThreads) {
      enableInlineCommentDialogMode()
      setInGridMode?.(false)
    } else {
      disableInlineCommentDialogMode()
      setInGridMode?.(true)
    }
    setShouldShowLineThreads(!shouldShowLineThreads)
  }, [disableInlineCommentDialogMode, enableInlineCommentDialogMode, setInGridMode, shouldShowLineThreads])
  const {
    annotations,
    isNewConversationDialogOpen,
    shouldStartNewConversationWithSuggestedChange,
    startNewConversation,
    startNewConversationWithSuggestedChange,
    openMarkerOrListDialog,
    selectAnnotation,
    selectThread,
    isMarkerListDialogOpen,
    closeNewConversationDialog,
    closeMarkerListDialog,
    closeConversationDetailsDialog,
    returnFocusRef,
    optimizedSelectedAnnotationId,
    optimizedSelectedThreadId,
    threadConnectionId,
    threads,
  } = useActionBarDialogs({
    cellId,
    actionBarRef: actionBarReturnFocusRef,
    onOpenInLineThread: toggleShowingInlineThreads,
  })

  const enterDialogMode = useCallback(
    (shouldFocusSelector = true) => {
      if (cellRef.current?.classList.contains('diff-text-cell')) {
        enableInlineCommentDialogMode()
        setInGridMode?.(false)
        // Focus the start conversation button after the cell has been converted to role="dialog"
        if (shouldFocusSelector) {
          setTimeout(() => {
            ;(cellRef.current?.querySelector('[aria-label="Start conversation"]') as HTMLButtonElement)?.focus()
          }, 0)
        }
      }
    },
    [enableInlineCommentDialogMode, setInGridMode],
  )

  /**
   * Open review thread for initial navigation
   */
  useEffect(() => {
    if (!commentingImplementation) return

    if (initialExpandedThreadId && optimizedSelectedThreadId !== initialExpandedThreadId) {
      const threadIds = threads.map(l => l.id)
      if (threadIds.includes(initialExpandedThreadId)) {
        selectThread(initialExpandedThreadId, {skipLineSelection: true})
      }
    }

    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialExpandedThreadId])

  /** Open review thread or annotation for global marker navigation */
  useEffect(() => {
    if (!markerNavigationImplementation) return

    const {activeGlobalMarkerID, onActivateGlobalMarkerNavigation} = markerNavigationImplementation
    if (activeGlobalMarkerID) {
      const threadIds = threads.map(l => l.id)
      const annotationIds = annotations.map(a => a.id)
      if (threadIds.includes(activeGlobalMarkerID)) {
        selectThread(activeGlobalMarkerID, {skipLineSelection: true})
        onActivateGlobalMarkerNavigation()
      } else if (annotationIds.includes(activeGlobalMarkerID)) {
        selectAnnotation(activeGlobalMarkerID, {skipLineSelection: true})
        onActivateGlobalMarkerNavigation()
      }
    }
  }, [selectThread, threads, markerNavigationImplementation, annotations, selectAnnotation])

  const handleAddComment = ({
    onCompleted,
    threadsConnectionId,
    ...args
  }: {
    filePath: string
    onCompleted?: (threadId: string, commentDatabaseId?: number) => void
    onError: (error: Error) => void
    side?: 'LEFT' | 'RIGHT' | undefined
    submitBatch?: boolean | undefined
    text: string
    threadsConnectionId?: string | undefined
  }) => {
    if (!commentingImplementation || !line) return

    // if there's a row selection, we want to add the thread to the last line of the selection
    const {leftLines, rightLines} = selectedDiffLines
    if (selectedDiffRowRange) {
      const linesToCheck = selectedDiffRowRange.endOrientation === 'left' ? leftLines : rightLines
      const lastSelectedLine = linesToCheck[linesToCheck.length - 1]
      if (lastSelectedLine && isDiffLine(lastSelectedLine) && lastSelectedLine.threadsData?.__id) {
        threadsConnectionId = lastSelectedLine.threadsData?.__id
      }
    }

    const handleCompleted = (threadId: string, commentDatabaseId?: number) => {
      onCompleted?.(threadId, commentDatabaseId)
      selectThread(threadId)
      if (diffInlineCommentsFeatureIsEnabled) setManuallyUpdateComments(threadId)
    }

    commentingImplementation.addThread({
      ...args,
      diffLine: line,
      isLeftSide,
      selectedDiffRowRange,
      threadsConnectionId,
      onCompleted: handleCompleted,
    })
  }

  const handleDeleteComment = ({
    onCompleted,
    ...args
  }: {
    commentConnectionId?: string
    commentId: string
    onCompleted?: () => void
    onError: (error: Error) => void
    threadCommentCount?: number
    threadsConnectionId?: string
    threadId: string
  }) => {
    if (!commentingImplementation || !line) return

    const handleCompleted = () => {
      onCompleted?.()
      // If there are no more comments on this line, focus on the cell
      if (threads.length <= 1) {
        closeConversationDetailsDialog()
        setTimeout(() => cellRef.current?.focus())
      }
    }
    commentingImplementation.deleteComment({
      ...args,
      onCompleted: handleCompleted,
      filePath,
    })
  }

  const suggestedChangesConfig = useSuggestedChanges(
    commentingImplementation?.suggestedChangesEnabled,
    line,
    shouldStartNewConversationWithSuggestedChange,
  )

  const closeFocusMode = useCallback(() => {
    disableInlineCommentDialogMode()
    setInGridMode?.(true)
  }, [disableInlineCommentDialogMode, setInGridMode])

  const handleGridModeReset = useCallback(() => {
    if (!isInDialogMode && (cellRef.current?.querySelectorAll(':focus') ?? []).length === 0) {
      disableInlineCommentDialogMode()
      setInGridMode?.(true)
    }
  }, [disableInlineCommentDialogMode, isInDialogMode, setInGridMode])

  const shouldAnimate = useRef(true)
  const {ghostUser} = useDiffContext()

  const inlineCommentJSX =
    isNewConversationDialogOpen && commentingImplementation ? (
      <StartConversation
        isDialog={false}
        addCommentDialogTitle={addCommentDialogTitle}
        anchorRef={cellRef}
        batchPending={commentBatchPending}
        batchingEnabled={commentingImplementation.batchingEnabled}
        commentBoxConfig={commentingImplementation.commentBoxConfig}
        filePath={filePath}
        isLeftSide={!!isLeftSide}
        isOpen={isNewConversationDialogOpen}
        lineNumber={line.blobLineNumber}
        repositoryId={repositoryId}
        returnFocusRef={returnFocusRef}
        subjectId={subjectId}
        suggestedChangesConfig={suggestedChangesConfig}
        threadsConnectionId={threadConnectionId}
        viewerData={viewerData}
        onAddComment={handleAddComment}
        onCloseCommentDialog={closeNewConversationDialog}
      />
    ) : null

  return (
    <Cell
      ref={cellRef}
      columnIndex={columnIndex}
      commentDialogOpen={isNewConversationDialogOpen}
      handleDiffCellClick={handleDiffCellClick}
      enterDialogMode={enterDialogMode}
      handleDiffSideCellSelectionBlocking={handleDiffSideCellSelectionBlocking}
      lineAnchor={lineAnchor}
      firstLineNumberSelection={firstLineNumberSelection}
      startConversation={startNewConversation}
      ContextMenu={
        <CellContextMenu
          copilotChatReference={copilotChatReference}
          showStartConversation={showStartConversation}
          handleViewMarkersSelection={openMarkerOrListDialog}
          startConversationCurrentLine={startNewConversation}
          startConversationWithSuggestedChange={startNewConversationWithSuggestedChange}
        />
      }
      className={clsx(`diff-text-cell ${isLeftSide ? 'left-side-diff-cell' : 'right-side-diff-cell'}`, {
        'border-right': isLeftSide && line.type !== 'HUNK',
      })}
      style={{
        backgroundColor: getBackgroundColor(line.type, false),
        paddingRight: commentIndicatorGutterSize,
      }}
      onBlur={(event: React.FocusEvent) => {
        handleCellBlur(event)
        handleGridModeReset()
      }}
      onFocus={handleCellFocus}
      onMouseEnter={handleCellMouseEnter}
      onMouseLeave={handleCellMouseLeave}
    >
      <code
        className={clsx('diff-text syntax-highlighted-line', {
          addition: line.type === 'ADDITION',
          deletion: line.type === 'DELETION',
        })}
      >
        {showTrimmedChar && <span className="diff-text-marker">{trimmedChar}</span>}
        {searchResultsForLine && searchResultsForLine.length > 0 && (
          <DiffHighlightedOverlay
            searchResults={searchResultsForLine}
            focusedSearchResult={focusedSearchResult}
            className={clsx('diff-text-inner', {
              'color-fg-muted': line.type === 'HUNK',
            })}
          />
        )}
        {/* Explicitly mark html as safe because it is server-sanitized */}
        <SafeHTMLDiv
          html={lineHtml as SafeHTMLString}
          className={clsx('diff-text-inner', {
            'color-fg-muted': line.type === 'HUNK',
          })}
        />
      </code>
      {line.displayNoNewLineWarning && <NoEntryIcon size={16} className="fgColor-danger" />}
      {isActionBarVisible && (
        <ActionBar
          shouldDisplayCollapseComments={diffInlineCommentsFeatureIsEnabled ? shouldShowLineThreads : false}
          copilotChatReference={copilotChatReference}
          authorAvatarUrl={viewerData.avatarUrl}
          authorLogin={viewerData.login}
          ref={actionBarReturnFocusRef}
          cellId={cellId}
          cellRef={cellRef}
          hasDraftComment={hasPersistedComment}
          showStartConversation={showStartConversation}
          onOpenInLineThread={toggleShowingInlineThreads}
        />
      )}
      {commentingImplementation && markerNavigationImplementation && (
        <>
          {diffInlineCommentsFeatureIsEnabled &&
          hasThreads &&
          (viewerData.commentsPreference === CommentsPreference.Visible || shouldShowLineThreads) ? (
            <InlineMarkers
              manuallyUpdateCommentsWithThisThreadId={manuallyUpdateCommentsWithThisThreadId}
              annotations={annotations}
              enterDialogMode={enterDialogMode}
              batchPending={commentBatchPending}
              batchingEnabled={commentingImplementation.batchingEnabled}
              commentingImplementation={{...commentingImplementation, deleteComment: handleDeleteComment}}
              conversationListThreads={threads}
              fileAnchor={fileAnchor}
              filePath={filePath}
              onCloseFocusMode={closeFocusMode}
              isMarkerListOpen={
                cellRef.current?.classList.contains('diff-text-cell') && threads.length > 0 ? true : false
              }
              repositoryId={repositoryId}
              returnFocusRef={returnFocusRef}
              selectedAnnotationId={optimizedSelectedAnnotationId}
              selectedThreadId={
                optimizedSelectedThreadId
                  ? optimizedSelectedThreadId
                  : cellRef.current?.classList.contains('diff-text-cell') && threads.length > 0
                    ? threads[0]?.id
                    : null
              }
              subjectId={subjectId}
              subject={subject}
              suggestedChangesConfig={suggestedChangesConfig}
              threadsConnectionId={threadConnectionId}
              onCloseConversationDialog={closeConversationDetailsDialog}
              onCloseConversationList={closeMarkerListDialog}
              onAnnotationSelected={selectAnnotation}
              onThreadSelected={selectThread}
              viewerData={viewerData}
              ghostUser={ghostUser}
              startConversationElementJSX={inlineCommentJSX}
            />
          ) : (
            <>
              <Markers
                annotations={annotations}
                batchPending={commentBatchPending}
                batchingEnabled={commentingImplementation.batchingEnabled}
                commentingImplementation={{...commentingImplementation, deleteComment: handleDeleteComment}}
                conversationAnchorRef={cellRef}
                conversationListAnchorRef={returnFocusRef}
                conversationListThreads={threads}
                fileAnchor={fileAnchor}
                filePath={filePath}
                isMarkerListOpen={isMarkerListDialogOpen}
                repositoryId={repositoryId}
                returnFocusRef={returnFocusRef}
                selectedAnnotationId={optimizedSelectedAnnotationId}
                selectedThreadId={optimizedSelectedThreadId}
                subjectId={subjectId}
                subject={subject}
                suggestedChangesConfig={suggestedChangesConfig}
                threadsConnectionId={threadConnectionId}
                onCloseConversationDialog={closeConversationDetailsDialog}
                onCloseConversationList={closeMarkerListDialog}
                onAnnotationSelected={selectAnnotation}
                onThreadSelected={selectThread}
                markerNavigationImplementation={markerNavigationImplementation}
                viewerData={viewerData}
                ghostUser={ghostUser}
              />

              <StartConversation
                addCommentDialogTitle={addCommentDialogTitle}
                anchorRef={cellRef}
                batchPending={commentBatchPending}
                batchingEnabled={commentingImplementation.batchingEnabled}
                commentBoxConfig={commentingImplementation.commentBoxConfig}
                filePath={filePath}
                isLeftSide={!!isLeftSide}
                isOpen={isNewConversationDialogOpen}
                lineNumber={line.blobLineNumber}
                repositoryId={repositoryId}
                returnFocusRef={returnFocusRef}
                subjectId={subjectId}
                suggestedChangesConfig={suggestedChangesConfig}
                threadsConnectionId={threadConnectionId}
                viewerData={viewerData}
                onAddComment={handleAddComment}
                onCloseCommentDialog={closeNewConversationDialog}
              />
            </>
          )}
        </>
      )}
      {!isActionBarVisible &&
        (!diffInlineCommentsFeatureIsEnabled || viewerData.commentsPreference === CommentsPreference.Collapsed) && (
          <div
            aria-hidden="true"
            style={{right: commentIndicatorRightPositioning}}
            className="position-absolute top-0 d-flex user-select-none"
          >
            <CommentIndicator
              shouldAnimateRef={shouldAnimate}
              lineSpacingPreference={viewerData.lineSpacingPreference}
            />
            {hasPersistedComment && (
              <InProgressCommentIndicator
                lineSpacingPreference={viewerData.lineSpacingPreference}
                authorAvatarUrl={viewerData.avatarUrl}
                authorLogin={viewerData.login}
              />
            )}
          </div>
        )}
      {summary && <DiffLineScreenReaderSummary summary={summary} />}
    </Cell>
  )
}

type LineNumberCellProps = React.PropsWithChildren<{
  columnIndex: number
  handleDiffCellClick: (event: React.MouseEvent<HTMLTableCellElement>) => void
  handleDiffSideCellSelectionBlocking: (event: React.MouseEvent) => void
  firstLineNumberSelection: React.MutableRefObject<number | null>
  filePath: string
  copilotChatReference?: FileDiffReference
}>

/**
 * Renders a line number cell
 */
export const LineNumberCell = memo(LineNumberCellUnmemoized)
export function LineNumberCellUnmemoized({
  children,
  columnIndex,
  handleDiffCellClick,
  handleDiffSideCellSelectionBlocking,
  firstLineNumberSelection,
  filePath,
  copilotChatReference,
  ...rest
}: LineNumberCellProps) {
  const cellRef = useRef<HTMLTableCellElement>(null)
  const cellId = useCellId(columnIndex)
  const {
    commentBatchPending,
    commentingEnabled,
    commentingImplementation,
    repositoryId,
    subject,
    subjectId,
    markerNavigationImplementation,
    viewerData,
  } = useDiffContext()

  const {diffLine, fileAnchor, isLeftSide} = useDiffLineContext()
  const line = diffLine as DiffLine
  const {selectedDiffRowRange, selectedDiffLines, updateSelectedDiffRowRange} = useSelectedDiffRowRangeContext()
  const addCommentDialogTitle = useCommentDialogTitle(line, !!isLeftSide)

  const showStartConversation: boolean = useMemo(() => {
    return viewerCanCommentOnLine(commentingEnabled, viewerData.viewerCanComment, line, selectedDiffLines)
  }, [commentingEnabled, viewerData, line, selectedDiffLines])

  const {handleCellBlur, handleCellFocus, handleCellMouseEnter, handleCellMouseLeave} = useActionBarFocus({
    cellRef,
  })
  const handleMouseEnterCell = useCallback(() => {
    if (firstLineNumberSelection && firstLineNumberSelection.current !== null) {
      updateSelectedDiffRowRange(
        fileAnchor,
        isLeftSide ? line.left : line.right,
        isLeftSide ? 'left' : 'right',
        true,
        true,
      )
    }
    handleCellMouseEnter()
  }, [
    fileAnchor,
    handleCellMouseEnter,
    isLeftSide,
    line.left,
    line.right,
    firstLineNumberSelection,
    updateSelectedDiffRowRange,
  ])

  const handleMouseDownOnNumberCell = useCallback(() => {
    updateSelectedDiffRowRange(
      fileAnchor,
      isLeftSide ? line.left : line.right,
      isLeftSide ? 'left' : 'right',
      false,
      true,
    )

    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const {ghostUser} = useDiffContext()

  const {
    annotations,
    isNewConversationDialogOpen,
    shouldStartNewConversationWithSuggestedChange,
    startNewConversation,
    startNewConversationWithSuggestedChange,
    openMarkerOrListDialog,
    isMarkerListDialogOpen,
    closeConversationDetailsDialog,
    closeMarkerListDialog,
    selectAnnotation,
    selectThread,
    closeNewConversationDialog,
    returnFocusRef,
    optimizedSelectedThreadId,
    optimizedSelectedAnnotationId,
    threadConnectionId,
    threads,
  } = useActionBarDialogs({
    cellId,
    actionBarRef: cellRef,
  })
  const handleAddComment = ({
    onCompleted,
    threadsConnectionId,
    ...args
  }: {
    filePath: string
    onCompleted?: (threadId: string, commentDatabaseId?: number) => void
    onError: (error: Error) => void
    side?: 'LEFT' | 'RIGHT' | undefined
    submitBatch?: boolean | undefined
    text: string
    threadsConnectionId?: string | undefined
  }) => {
    if (!commentingImplementation || !line) return

    const handleCompleted = (threadId: string, commentDatabaseId?: number) => {
      onCompleted?.(threadId, commentDatabaseId)
      selectThread(threadId)
    }

    // if there's a row selection, we want to add the thread to the last line of the selection
    const {leftLines, rightLines} = selectedDiffLines
    if (selectedDiffRowRange) {
      const linesToCheck = selectedDiffRowRange.endOrientation === 'left' ? leftLines : rightLines
      const lastSelectedLine = linesToCheck[linesToCheck.length - 1]
      if (lastSelectedLine && isDiffLine(lastSelectedLine) && lastSelectedLine.threadsData?.__id) {
        threadsConnectionId = lastSelectedLine.threadsData?.__id
      }
    }

    commentingImplementation.addThread({
      ...args,
      diffLine: line,
      selectedDiffRowRange,
      threadsConnectionId,
      onCompleted: handleCompleted,
    })
  }

  const handleDeleteComment = ({
    onCompleted,
    ...args
  }: {
    commentConnectionId?: string
    commentId: string
    onCompleted?: () => void
    onError: (error: Error) => void
    threadCommentCount?: number
    threadsConnectionId?: string
    threadId: string
  }) => {
    if (!commentingImplementation || !line) return

    const handleCompleted = () => {
      onCompleted?.()

      // If there are no more comments on this line, focus on the cell
      if (threads.length <= 1) {
        closeConversationDetailsDialog()
        setTimeout(() => cellRef.current?.focus())
      }
    }
    commentingImplementation.deleteComment({
      ...args,
      onCompleted: handleCompleted,
      filePath,
    })
  }

  const suggestedChangesConfig = useSuggestedChanges(
    commentingImplementation?.suggestedChangesEnabled,
    line,
    shouldStartNewConversationWithSuggestedChange,
  )

  return (
    <>
      <Cell
        ref={cellRef}
        className={clsx('diff-line-number', DIMMED_LINE_NUMBER_TYPES.includes(line.type) && 'diff-line-number-neutral')}
        columnIndex={columnIndex}
        commentDialogOpen={isNewConversationDialogOpen}
        handleDiffCellClick={handleDiffCellClick}
        handleDiffSideCellSelectionBlocking={handleDiffSideCellSelectionBlocking}
        firstLineNumberSelection={firstLineNumberSelection}
        startConversation={startNewConversation}
        style={{backgroundColor: getBackgroundColor(line.type, true), textAlign: 'center'}}
        ContextMenu={
          <CellContextMenu
            copilotChatReference={copilotChatReference}
            showStartConversation={showStartConversation}
            handleViewMarkersSelection={openMarkerOrListDialog}
            startConversationCurrentLine={startNewConversation}
            startConversationWithSuggestedChange={startNewConversationWithSuggestedChange}
          />
        }
        onBlur={handleCellBlur}
        onFocus={handleCellFocus}
        handleDiffCellMouseDown={handleMouseDownOnNumberCell}
        onMouseEnter={handleMouseEnterCell}
        onMouseLeave={handleCellMouseLeave}
        {...rest}
      >
        <code>{children}</code>
      </Cell>
      {commentingImplementation && markerNavigationImplementation && (
        <>
          <Markers
            annotations={annotations}
            batchPending={commentBatchPending}
            batchingEnabled={commentingImplementation.batchingEnabled}
            commentingImplementation={{...commentingImplementation, deleteComment: handleDeleteComment}}
            conversationAnchorRef={cellRef}
            conversationListAnchorRef={returnFocusRef}
            conversationListThreads={threads}
            fileAnchor={fileAnchor}
            filePath={filePath}
            isMarkerListOpen={isMarkerListDialogOpen}
            repositoryId={repositoryId}
            returnFocusRef={returnFocusRef}
            selectedAnnotationId={optimizedSelectedAnnotationId}
            selectedThreadId={optimizedSelectedThreadId}
            subjectId={subjectId}
            subject={subject}
            suggestedChangesConfig={suggestedChangesConfig}
            threadsConnectionId={threadConnectionId}
            markerNavigationImplementation={markerNavigationImplementation}
            onCloseConversationDialog={closeConversationDetailsDialog}
            onCloseConversationList={closeMarkerListDialog}
            onThreadSelected={selectThread}
            onAnnotationSelected={selectAnnotation}
            viewerData={viewerData}
            ghostUser={ghostUser}
          />
          <StartConversation
            addCommentDialogTitle={addCommentDialogTitle}
            align="start"
            anchorRef={cellRef}
            batchPending={commentBatchPending}
            batchingEnabled={commentingImplementation.batchingEnabled}
            commentBoxConfig={commentingImplementation.commentBoxConfig}
            filePath={filePath}
            isLeftSide={!!isLeftSide}
            isOpen={isNewConversationDialogOpen}
            lineNumber={line.blobLineNumber}
            repositoryId={repositoryId}
            returnFocusRef={returnFocusRef}
            subjectId={subjectId}
            suggestedChangesConfig={suggestedChangesConfig}
            threadsConnectionId={threadConnectionId}
            viewerData={viewerData}
            onAddComment={handleAddComment}
            onCloseCommentDialog={closeNewConversationDialog}
          />
        </>
      )}
    </>
  )
}

/**
 * Renders a hunk header cell
 */
export function HunkCell({
  ContextMenu,
  renderHunkButton,
  searchResultsForLine,
  focusedSearchResult,
}: {
  ContextMenu?: ReactElement
  renderHunkButton?: (additionalProps: PrunedIconButtonProps) => ReactNode | null
  searchResultsForLine?: DiffMatchContent[]
  focusedSearchResult?: number
}) {
  const cellRef = useRef<HTMLTableCellElement>(null)
  const [cellProps, buttonProps] = useGridCellButtonProps(cellRef)
  const {diffLine} = useDiffLineContext()
  const line = diffLine as DiffLine

  return (
    <Cell
      ref={cellRef}
      ContextMenu={ContextMenu}
      colSpan={4}
      columnIndex={0}
      style={{backgroundColor: 'var(--bgColor-accent-muted, var(--color-accent-subtle))', flexGrow: 1}}
      {...cellProps}
    >
      <div className="d-flex flex-row">
        {renderHunkButton?.(buttonProps) ?? <HunkKebabIcon />}
        <code className="diff-text-cell hunk">
          {searchResultsForLine && searchResultsForLine.length > 0 && (
            <DiffHighlightedOverlay
              searchResults={searchResultsForLine}
              focusedSearchResult={focusedSearchResult}
              className={clsx('diff-text-inner', {
                'color-fg-muted': line.type === 'HUNK',
              })}
            />
          )}
          {/* Explicitly mark html as safe because it is server-sanitized */}
          <SafeHTMLDiv className="diff-text-inner color-fg-muted" html={line.html as SafeHTMLString} />
        </code>
      </div>
    </Cell>
  )
}

/**
 * Renders an empty cell
 */
export function EmptyCell({columnIndex, showRightBorder}: {columnIndex: number; showRightBorder?: boolean}) {
  return (
    <Cell
      ContextMenu={<EmptyCellContextMenu />}
      className={clsx('empty-diff-line', {'border-right': showRightBorder})}
      columnIndex={columnIndex}
    />
  )
}

export function getBackgroundColor(lineType: DiffLineType, isNumber = false): string | undefined {
  switch (lineType) {
    case 'ADDITION':
      return isNumber
        ? 'var(--diffBlob-additionNum-bgColor, var(--diffBlob-addition-bgColor-num))'
        : 'var(--diffBlob-additionLine-bgColor, var(--diffBlob-addition-bgColor-line))'
    case 'DELETION':
      return isNumber
        ? 'var(--diffBlob-deletionNum-bgColor, var(--diffBlob-deletion-bgColor-num))'
        : 'var(--diffBlob-deletionLine-bgColor, var(--diffBlob-deletion-bgColor-line))'
    case 'HUNK':
      return isNumber
        ? 'var(--diffBlob-hunkNum-bgColor-rest, var(--diffBlob-hunk-bgColor-num))'
        : 'var(--diffBlob-hunkLine-bgColor, var(--bgColor-accent-muted))'
    case 'EMPTY':
      return isNumber
        ? 'var(--diffBlob-emptyNum-bgColor, var(--diffBlob-hunk-bgColor-num))'
        : 'var(--diffBlob-emptyLine-bgColor, var(--bgColor-accent-muted))'
    default:
      return undefined
  }
}
