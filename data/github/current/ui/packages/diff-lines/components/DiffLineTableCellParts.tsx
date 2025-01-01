import {StartConversation, usePersistedDiffCommentData} from '@github-ui/conversations'
import {InlineMarkers} from '@github-ui/conversations/inline-markers'
import type {DiffLineType} from '@github-ui/diffs/types'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {SafeHTMLDiv} from '@github-ui/safe-html'
import {useSafeAsyncCallback} from '@github-ui/use-safe-async-callback'
import {CommentsPreference} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'
import {KebabHorizontalIcon, NoEntryIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import {ActionList, ActionMenu} from '@primer/react'
import type React from 'react'
import type {ComponentPropsWithoutRef, FocusEvent, KeyboardEvent, ReactElement, ReactNode, RefObject} from 'react'
import {forwardRef, memo, useCallback, useEffect, useId, useImperativeHandle, useMemo, useRef, useState} from 'react'
import {useCopyCode} from '../hooks/use-copy-code'
import {useDiffContext} from '../contexts/DiffContext'
import {useDiffLineContext} from '../contexts/DiffLineContext'
import {useMarkersDialogContext} from '../contexts/MarkersDialogContext'
import type {SelectedDiffLines} from '../contexts/SelectedDiffRowRangeContext'
import {useSelectedDiffRowRangeContext} from '../contexts/SelectedDiffRowRangeContext'
import {
  anchorLinkForSelection,
  calculateDiffLineCodeCellGutter,
  cellIdFrom,
  getLineBackgroundColor,
  isContextDiffLine,
  isDiffLine,
  lineAcceptsComments,
  lineNeedsMarkerPadding,
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
import {useInlineCommentDialogModeContext} from '@github-ui/conversations/inline-comment-dialog-mode-context'
import {copyText} from '@github-ui/copy-to-clipboard'
import styles from './DiffLineTableCellParts.module.css'
import {useMarkersDialogStatus} from '../hooks/use-markers-dialog-status'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

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

export function useCommentDialogTitle(diffLine: DiffLine, isLeftSide: boolean, isLineSelected: boolean) {
  const {selectedDiffRowRange} = useSelectedDiffRowRangeContext()
  return useMemo(() => {
    let text = 'Add a comment on'
    const isMultiLineComment: boolean =
      !!selectedDiffRowRange && selectedDiffRowRange.startLineNumber !== selectedDiffRowRange.endLineNumber

    if (selectedDiffRowRange && isMultiLineComment && isLineSelected) {
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
  }, [diffLine, isLeftSide, selectedDiffRowRange, isLineSelected])
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
  hasThreads?: boolean
  handleDiffCellClick?: (event: React.MouseEvent<HTMLTableCellElement>) => void
  handleDiffSideCellSelectionBlocking?: (event: React.MouseEvent) => void
  handleExitDialogMode?: () => void
  handleHideMarkersFromFocus?: (state: boolean) => void
  handleDiffCellMouseDown?: () => void
  handleStartConversation?: () => void
  handleUserClosedMarkersDialog?: () => void
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
    handleExitDialogMode,
    handleHideMarkersFromFocus,
    handleDiffSideCellSelectionBlocking,
    handleStartConversation,
    handleUserClosedMarkersDialog,
    lineAnchor,
    firstLineNumberSelection,
    commentDialogOpen,
    enterDialogMode,
    hasThreads,
    ...props
  }: CellProps,
  forwardedRef,
) {
  const {diffLine, fileAnchor, isRowSelected, isLeftSide} = useDiffLineContext()
  const line = diffLine as DiffLine
  const cellRef = useRef<HTMLTableCellElement>(null)

  // delegate the internal ref to the forwarded one if there is one
  useImperativeHandle<HTMLTableCellElement | null, HTMLTableCellElement | null>(forwardedRef, () => cellRef.current, [])

  const [showContextMenu, setShowContextMenu] = useState(false)
  const {selectedDiffRowRange} = useSelectedDiffRowRangeContext()
  const {disableInlineCommentDialogMode, isInDialogMode} = useInlineCommentDialogModeContext()
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

    if (isInDialogMode) {
      const targetIsNotInsideInlineMarkersDialog = !(e.target as HTMLElement).closest('[data-inline-markers]')
      const targetIsNotInsideOfDialogPortal = !(e.target as HTMLElement).closest('#__primerPortalRoot__')

      if (targetIsNotInsideInlineMarkersDialog && targetIsNotInsideOfDialogPortal) {
        disableInlineCommentDialogMode()
      }
    }
  })

  useEffect(() => {
    ssrSafeDocument?.addEventListener('mousedown', handleClickOutside)
    return () => ssrSafeDocument?.removeEventListener('mousedown', handleClickOutside)
  }, [handleClickOutside])

  useEffect(() => {
    // ensure we don't leak the event listener on unmount
    return () => ssrSafeDocument?.removeEventListener('mousedown', handleClickOutside)

    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const copyAnchorLink = useCallback(() => {
    const link = anchorLinkForSelection({line, range: selectedDiffRowRange, fileAnchor})
    if (link) copyText(link)
  }, [fileAnchor, line, selectedDiffRowRange])

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

    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [handleDiffSideCellSelectionBlocking],
  )

  const exitDialogMode = useCallback(() => {
    cellRef.current?.focus()
    disableInlineCommentDialogMode()
    handleExitDialogMode?.()
    handleUserClosedMarkersDialog?.()
  }, [disableInlineCommentDialogMode, handleExitDialogMode, handleUserClosedMarkersDialog])

  const copyCode = useCopyCode({
    fileAnchor,
  })

  const handleOnKeyPress = useCallback(
    async (e: React.KeyboardEvent<HTMLTableCellElement>) => {
      // Handle copy code for `mod + c`
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (e.target === cellRef.current && (e?.metaKey || e?.ctrlKey) && e.key === 'c') {
        e.preventDefault() // Prevent default browser copy from overriding our custom copy.
        await copyCode()
        return
      }

      // Handle copy anchor link for `mod + alt + y`
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (e.target === cellRef.current && (e?.metaKey || e?.ctrlKey) && e.altKey && e.key === 'y') {
        copyAnchorLink()
        return
      }

      // Handle escape press on the row
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (cellRef.current?.contains(e.target as Node) && e?.key === 'Escape') {
        exitDialogMode()
        return
      }

      //when the user has the final element in the focus loop focused and hits tab, we want to wrap them back
      //around to the beginning and focus the first element in the loop, which is the collapse button
      if (
        cellRef.current?.contains(e.target as Node) &&
        (e.target as HTMLElement).getAttribute('data-exit-dialog-mode-button') === 'true' &&
        !e?.shiftKey &&
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        e?.key === 'Tab'
      ) {
        //prevent the default behavior and instead wrap around to focus the first collapse button
        e.preventDefault()
        ;(cellRef.current?.querySelector('[data-is-first-collapse-button="true"]') as HTMLElement)?.focus()
        return
      }

      //when the user has the first element in the focus loop focused and hits shift+tab, we want to wrap them back
      //around to the end and focus the last element in the loop, which is the exit dialog button
      if (
        cellRef.current?.contains(e.target as Node) &&
        (e.target as HTMLElement).getAttribute('data-is-first-collapse-button') === 'true' &&
        e?.shiftKey &&
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        e?.key === 'Tab'
      ) {
        //prevent the default behavior and instead wrap around to focus the close button
        e.preventDefault()
        ;(cellRef.current?.querySelector('[data-exit-dialog-mode-button="true"]') as HTMLElement)?.focus()
        return
      }
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (e.target === cellRef.current && e.key === 'Enter') {
        enterDialogMode?.()

        if (hasThreads === false) {
          handleStartConversation?.()
        }
        e.preventDefault()
      }
    },
    [copyCode, copyAnchorLink, exitDialogMode, enterDialogMode, hasThreads, handleStartConversation],
  )

  const inlineDialogHeadingId = `inline-dialog-heading-${useId()}`
  return (
    <td
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
      onKeyDown={handleOnKeyPress}
      onBlur={e => (e.target.ariaSelected = 'false')}
      onClick={handleDiffCellClick}
      onFocus={e => (e.target.ariaSelected = 'true')}
      onMouseDown={handleMouseDown}
      onMouseUp={handleMouseUp}
      aria-labelledby={isInDialogMode ? inlineDialogHeadingId : undefined}
      {...props}
    >
      {isInDialogMode && (
        <h1 id={inlineDialogHeadingId} className="sr-only">
          Comment view
        </h1>
      )}
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
    </td>
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

const ContentCellUnmemoized = forwardRef<HTMLTableCellElement, ContentCellProps>(function ContentCellUnmemoized(
  {
    searchResultsForLine,
    focusedSearchResult,
    columnIndex,
    lineAnchor,
    firstLineNumberSelection,
    handleDiffCellClick,
    handleDiffSideCellSelectionBlocking,
    filePath,
    copilotChatReference,
  }: ContentCellProps,
  forwardedRef,
) {
  const {diffLine, fileAnchor, isLeftSide, isRowSelected} = useDiffLineContext()
  const line = diffLine as DiffLine

  const lineTypeCharacterCorrectionEnabled = useFeatureFlag('react_diff_line_type_character_correction')
  const [lineHtml, lineTypeCharacter] = trimContentLine(line.html, line.type, lineTypeCharacterCorrectionEnabled)
  const showLineTypeCharacter = lineTypeCharacter && ['+', '-'].includes(lineTypeCharacter)

  const [manuallyUpdateCommentsWithThisThreadId, setManuallyUpdateComments] = useState('')
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

  // When a user closes a dialog launched from either the action bar or the context menu, we want to return focus to the
  // element that triggered the dialog.
  const actionBarReturnFocusRef = useRef<HTMLButtonElement | null>(null)
  const cellRef = useRef<HTMLTableCellElement>(null)

  // delegate the internal ref to the forwarded one if there is one
  useImperativeHandle<HTMLTableCellElement | null, HTMLTableCellElement | null>(forwardedRef, () => cellRef.current, [])

  const hasThreads = !!line.threadsData?.threads?.length || !!line.annotationsData?.annotations?.length
  const commentIndicatorGutterSize = calculateDiffLineCodeCellGutter({
    hasThreads: hasThreads && viewerData.commentsPreference === CommentsPreference.Collapsed,
  })

  const addCommentDialogTitle = useCommentDialogTitle(line, !!isLeftSide, isRowSelected)

  const cellId = useCellId(columnIndex)
  const {handleCellBlur, handleCellFocus, handleCellMouseEnter, handleCellMouseLeave} = useActionBarFocus({
    cellRef,
  })

  const inlineMarkersRef = useRef<HTMLDivElement>(null)
  /**
   * The `markersStatus` state tracks whether the user has manually expanded/minimized
   * inline comment markers in the diff view while the "Collapsed" CommentsPreference setting is enabled
   * This state is critical for preserving a mouse user's intent regarding the visibility of
   * inline markers during their interaction with the diff view while in CommentsPreference is Collapsed.
   */
  const [markersStatus, dispatchMarkersStatus] = useMarkersDialogStatus(viewerData.commentsPreference)

  const enterDialogMode = useCallback(
    (shouldFocusSelector = true) => {
      if (cellRef.current?.classList.contains('diff-text-cell')) {
        enableInlineCommentDialogMode()
        dispatchMarkersStatus('USER_EXPANDED_MARKERS')
        // Focus the start conversation button after the cell has been converted to role="dialog"
        if (shouldFocusSelector) {
          setTimeout(() => {
            ;(cellRef.current?.querySelector('[data-first-marker="true"]') as HTMLElement)?.focus()
          }, 0)
        }
      }
    },
    [dispatchMarkersStatus, enableInlineCommentDialogMode],
  )

  const closeFocusMode = useCallback(() => {
    // A setTimeout is needed to ensure that the focus is restored to the cellRef after the dialog is closed, otherwise focus might be lost
    setTimeout(() => cellRef.current?.focus())
    disableInlineCommentDialogMode()
    dispatchMarkersStatus('USER_MINIMIZED_MARKERS')
  }, [disableInlineCommentDialogMode, dispatchMarkersStatus])

  const toggleViewingMarkers = useCallback(() => {
    if (viewerData.commentsPreference === CommentsPreference.Collapsed && markersStatus.showMarkers) {
      closeFocusMode()
    } else {
      enterDialogMode()
    }
  }, [closeFocusMode, enterDialogMode, markersStatus.showMarkers, viewerData.commentsPreference])

  const {
    annotations,
    isNewConversationDialogOpen,
    shouldStartNewConversationWithSuggestedChange,
    startNewConversation,
    startNewConversationWithSuggestedChange,
    selectAnnotation,
    selectThread,
    closeNewConversation,
    closeMarkerListDialog,
    returnFocusRef,
    optimizedSelectedAnnotationId,
    optimizedSelectedThreadId,
    threads,
  } = useActionBarDialogs({
    cellId,
    actionBarRef: actionBarReturnFocusRef,
    onOpenInLineThread: enterDialogMode,
  })

  const showStartConversation: boolean = useMemo(() => {
    if (isNewConversationDialogOpen) {
      return false
    }

    return viewerCanCommentOnLine(commentingEnabled, viewerData.viewerCanComment, line, selectedDiffLines)
  }, [isNewConversationDialogOpen, commentingEnabled, viewerData.viewerCanComment, line, selectedDiffLines])

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

    // eslint-disable-next-line react-hooks/react-compiler
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
      setManuallyUpdateComments(threadId)
    }

    commentingImplementation.addThread({
      ...args,
      diffLine: line,
      isLeftSide,
      isLineSelected: isRowSelected,
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

  const handleStartNewConversation = useCallback(() => {
    enterDialogMode?.()
    startNewConversation?.()
  }, [enterDialogMode, startNewConversation])

  const handleGridModeReset = useCallback(() => {
    if (!isInDialogMode && (cellRef.current?.querySelectorAll(':focus') ?? []).length === 0) {
      disableInlineCommentDialogMode()
    }
  }, [disableInlineCommentDialogMode, isInDialogMode])

  const shouldAnimate = useRef(true)
  const {ghostUser} = useDiffContext()

  const copyCode = useCopyCode({
    fileAnchor,
  })

  const showInlineComments = useMemo(() => {
    if (hasThreads && viewerData.commentsPreference === CommentsPreference.Collapsed) {
      return !markersStatus.userMinimized
    }

    if (!isNewConversationDialogOpen && !hasThreads) return false
    if (!commentingEnabled) return false

    if (viewerData.commentsPreference === CommentsPreference.Collapsed) {
      if (isNewConversationDialogOpen) return true
      if (isInDialogMode) return true
    }

    if (viewerData.commentsPreference === CommentsPreference.Visible) {
      if (hasThreads) return true
      if (isNewConversationDialogOpen) return true
      if (markersStatus.showMarkers) return true
    }

    return false
  }, [
    commentingEnabled,
    hasThreads,
    isInDialogMode,
    isNewConversationDialogOpen,
    markersStatus.showMarkers,
    markersStatus.userMinimized,
    viewerData.commentsPreference,
  ])

  const lineHasMarkerPadding = useMemo(() => lineNeedsMarkerPadding(line), [line])

  return (
    <Cell
      ref={cellRef}
      columnIndex={columnIndex}
      commentDialogOpen={isNewConversationDialogOpen}
      handleDiffCellClick={handleDiffCellClick}
      enterDialogMode={enterDialogMode}
      handleDiffSideCellSelectionBlocking={handleDiffSideCellSelectionBlocking}
      handleExitDialogMode={() => dispatchMarkersStatus('USER_EXITED_MARKERS_DIALOG')}
      handleUserClosedMarkersDialog={() => dispatchMarkersStatus('USER_MINIMIZED_MARKERS')}
      lineAnchor={lineAnchor}
      firstLineNumberSelection={firstLineNumberSelection}
      handleStartConversation={handleStartNewConversation}
      hasThreads={hasThreads}
      ContextMenu={
        <CellContextMenu
          shouldDisplayCollapseComments={showInlineComments}
          copilotChatReference={copilotChatReference}
          showStartConversation={showStartConversation}
          handleViewMarkersSelection={toggleViewingMarkers}
          startConversationCurrentLine={handleStartNewConversation}
          startConversationWithSuggestedChange={startNewConversationWithSuggestedChange}
        />
      }
      className={clsx(
        `diff-text-cell ${isLeftSide ? 'left-side-diff-cell' : 'right-side-diff-cell'} ${
          lineHasMarkerPadding ? 'pt-4' : ''
        }`,
        {
          'border-right': isLeftSide && line.type !== 'HUNK',
        },
      )}
      style={{
        backgroundColor: getLineBackgroundColor(line.type, false, isRowSelected),
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
        {showLineTypeCharacter && <span className="diff-text-marker">{lineTypeCharacter}</span>}
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
          shouldDisplayCollapseComments={markersStatus.showMarkers}
          copilotChatReference={copilotChatReference}
          authorAvatarUrl={viewerData.avatarUrl}
          authorLogin={viewerData.login}
          ref={actionBarReturnFocusRef}
          cellId={cellId}
          cellRef={cellRef}
          hasDraftComment={hasPersistedComment}
          showStartConversation={showStartConversation}
          onOpenInLineThread={enterDialogMode}
          handleCopyCode={copyCode}
          toggleViewingMarkers={toggleViewingMarkers}
        />
      )}
      {commentingImplementation && markerNavigationImplementation && (
        <>
          {showInlineComments ? (
            <InlineMarkers
              gutterSizeOffset={commentIndicatorGutterSize}
              inlineMarkersRef={inlineMarkersRef}
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
              isRowSelected={isRowSelected}
              lineType={line.type}
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
              onCloseConversationList={closeMarkerListDialog}
              onAnnotationSelected={selectAnnotation}
              onThreadSelected={selectThread}
              viewerData={viewerData}
              ghostUser={ghostUser}
            >
              {isNewConversationDialogOpen && (
                <div
                  className={clsx(
                    ' border rounded-2 color-border-default',
                    threads.length === 0 ? 'mt-2 mb-1' : 'mt-2 mb-1',
                  )}
                >
                  <StartConversation
                    isDialog={false}
                    addCommentDialogTitle={addCommentDialogTitle}
                    anchorRef={cellRef}
                    batchPending={commentBatchPending}
                    batchingEnabled={commentingImplementation.batchingEnabled}
                    commentBoxConfig={commentingImplementation.commentBoxConfig}
                    commentBoxSubject={commentingImplementation.commentBoxSubject}
                    filePath={filePath}
                    isLeftSide={!!isLeftSide}
                    isOpen={isNewConversationDialogOpen}
                    lineNumber={isRowSelected ? selectedDiffRowRange?.endLineNumber : line.blobLineNumber}
                    repositoryId={repositoryId}
                    returnFocusRef={returnFocusRef}
                    startLineNumber={isRowSelected ? selectedDiffRowRange?.startLineNumber : undefined}
                    subjectId={subjectId}
                    suggestedChangesConfig={suggestedChangesConfig}
                    viewerData={viewerData}
                    onAddComment={handleAddComment}
                    onCloseCommentDialog={() => {
                      closeFocusMode()
                      closeNewConversation()
                    }}
                  />
                </div>
              )}
            </InlineMarkers>
          ) : null}
        </>
      )}
      {!isActionBarVisible && viewerData.commentsPreference === CommentsPreference.Collapsed && (
        <>
          <div
            aria-hidden="true"
            style={{left: viewerData.lineSpacingPreference === 'compact' ? '-1px' : '-2px'}}
            className={clsx('position-absolute top-0 d-flex user-select-none', styles['in-progress-comment-indicator'])}
          >
            {hasPersistedComment && (
              <InProgressCommentIndicator
                lineSpacingPreference={viewerData.lineSpacingPreference}
                authorAvatarUrl={viewerData.avatarUrl}
                authorLogin={viewerData.login}
              />
            )}
          </div>
          <div
            aria-hidden="true"
            className={clsx('position-absolute top-0 d-flex user-select-none', styles['comment-indicator'])}
          >
            <CommentIndicator
              shouldAnimateRef={shouldAnimate}
              lineSpacingPreference={viewerData.lineSpacingPreference}
            />
          </div>
        </>
      )}
      <DiffLineScreenReaderSummary diffLine={line} />
    </Cell>
  )
})

export const ContentCell = memo(ContentCellUnmemoized)

type LineNumberCellProps = React.PropsWithChildren<{
  columnIndex: number
  handleDiffCellClick: (event: React.MouseEvent<HTMLTableCellElement>) => void
  handleDiffSideCellSelectionBlocking: (event: React.MouseEvent) => void
  firstLineNumberSelection: React.MutableRefObject<number | null>
  filePath: string
  copilotChatReference?: FileDiffReference
  contentRef: React.RefObject<HTMLTableCellElement>
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
  contentRef,
  ...rest
}: LineNumberCellProps) {
  const cellRef = useRef<HTMLTableCellElement>(null)
  const {diffLine, fileAnchor, isLeftSide, isRowSelected} = useDiffLineContext()
  const line = diffLine as DiffLine
  const {updateSelectedDiffRowRange} = useSelectedDiffRowRangeContext()

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
  }, [fileAnchor, isLeftSide, line.left, line.right, firstLineNumberSelection, updateSelectedDiffRowRange])

  const handleMouseDownOnNumberCell = useCallback(() => {
    updateSelectedDiffRowRange(
      fileAnchor,
      isLeftSide ? line.left : line.right,
      isLeftSide ? 'left' : 'right',
      false,
      true,
    )
  }, [fileAnchor, isLeftSide, line.left, line.right, updateSelectedDiffRowRange])

  return (
    <Cell
      ref={cellRef}
      className={clsx(
        'diff-line-number position-relative',
        DIMMED_LINE_NUMBER_TYPES.includes(line.type) && 'diff-line-number-neutral',
      )}
      columnIndex={columnIndex}
      handleDiffCellClick={handleDiffCellClick}
      handleDiffSideCellSelectionBlocking={handleDiffSideCellSelectionBlocking}
      firstLineNumberSelection={firstLineNumberSelection}
      style={{backgroundColor: getLineBackgroundColor(line.type, true, isRowSelected), textAlign: 'center'}}
      handleDiffCellMouseDown={handleMouseDownOnNumberCell}
      onMouseEnter={handleMouseEnterCell}
      {...rest}
    >
      <code>{children}</code>
    </Cell>
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
      className="diff-hunk-cell"
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
