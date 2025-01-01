import type {RefObject} from 'react'
import {useCallback, useMemo, useState} from 'react'

import {useMarkersDialogContext} from '../contexts/MarkersDialogContext'
import type {DiffAnnotation, ThreadSummary} from '@github-ui/conversations'
import {useSelectedDiffRowRangeContext} from '../contexts/SelectedDiffRowRangeContext'
import {useDiffLineContext} from '../contexts/DiffLineContext'
import {useStableCallback} from './use-stable-callback'
import {useAnalytics} from '@github-ui/use-analytics'

type ActionBarDialogs = {
  // New conversation
  isNewConversationDialogOpen: boolean
  startNewConversation: () => void
  startNewConversationWithSuggestedChange: () => void
  closeNewConversation: () => void
  shouldStartNewConversationWithSuggestedChange: boolean | undefined

  // Context menus
  isContextMenuOpen: boolean
  openContextMenu: () => void
  openContextMenuFromActionBar: () => void
  closeContextMenu: () => void
  toggleContextMenu: () => void
  toggleContextMenuFromActionBar: () => void

  optimizedSelectedThreadId: string | undefined
  optimizedSelectedAnnotationId: string | undefined
  selectThread: (threadId: string, opts?: {skipLineSelection?: boolean}) => void
  selectAnnotation: (annotationId: string, opts?: {skipLineSelection?: boolean}) => void
  openMarkersDialog: () => void
  closeMarkerListDialog: () => void

  // Misc
  annotations: DiffAnnotation[]
  returnFocusRef: RefObject<HTMLElement>
  threads: ThreadSummary[]
  anyMenuOpen: boolean
}

export function useActionBarDialogs({
  cellId,
  actionBarRef,
  onOpenInLineThread,
}: {
  cellId?: string
  actionBarRef: RefObject<HTMLElement>
  onOpenInLineThread?: () => void
}): ActionBarDialogs {
  const {replaceSelectedDiffRowRange} = useSelectedDiffRowRangeContext()
  const {fileAnchor} = useDiffLineContext()

  const [returnFocusRef, setReturnFocusRef] = useState<RefObject<HTMLElement>>(actionBarRef)
  const {
    annotations,
    openDialog,
    closeDialog,
    selectedAnnotationId,
    selectAnnotationId,
    selectedThreadId,
    selectThreadId,
    openContextMenuCell,
    openNewConversationCell,
    openMarkerDetailsCell,
    threads,
    anyMenuOpen,
  } = useMarkersDialogContext()

  const {sendAnalyticsEvent} = useAnalytics()

  const isNewConversationDialogOpen = useMemo(
    () => openNewConversationCell?.cellId === cellId,
    [cellId, openNewConversationCell],
  )

  const shouldStartNewConversationWithSuggestedChange = useMemo(
    () => openNewConversationCell?.withSuggestedChange,
    [openNewConversationCell],
  )

  // Internal
  const openNewConversationDialog = useCallback(
    (opts?: {withSuggestedChange?: boolean}) => {
      onOpenInLineThread?.()
      openDialog('new-conversation', cellId, opts)
    },
    [cellId, onOpenInLineThread, openDialog],
  )

  const startNewConversation = useCallback(() => {
    openNewConversationDialog()
  }, [openNewConversationDialog])

  const startNewConversationWithSuggestedChange = useCallback(() => {
    openNewConversationDialog({withSuggestedChange: true})
    sendAnalyticsEvent('diff.start_new_conversation_with_suggested_change', 'CELL_CONTEXT_MENU')
  }, [openNewConversationDialog, sendAnalyticsEvent])

  const closeNewConversation = useCallback(() => {
    closeDialog('new-conversation')
  }, [closeDialog])

  // Context menus
  const isContextMenuOpen = useMemo(() => openContextMenuCell === cellId, [cellId, openContextMenuCell])

  const openContextMenu = useCallback(() => {
    openDialog('context-menu', cellId)
  }, [cellId, openDialog])

  const openContextMenuFromActionBar = useCallback(() => {
    setReturnFocusRef(actionBarRef)
    openContextMenu()
  }, [actionBarRef, openContextMenu])

  const closeContextMenu = useCallback(() => {
    closeDialog('context-menu')
  }, [closeDialog])

  const toggleContextMenu = useCallback(() => {
    if (isContextMenuOpen) {
      closeContextMenu()
    } else {
      openContextMenu()
    }
  }, [closeContextMenu, isContextMenuOpen, openContextMenu])

  const toggleContextMenuFromActionBar = useCallback(() => {
    setReturnFocusRef(actionBarRef)
    toggleContextMenu()
  }, [actionBarRef, toggleContextMenu])

  // Viewing conversation details

  // Only pass the selected thread if the cell is open to prevent unnecessary re-renders
  const optimizedSelectedThreadId = useMemo(
    () => (openMarkerDetailsCell === cellId ? selectedThreadId : undefined),
    [cellId, openMarkerDetailsCell, selectedThreadId],
  )

  // Only pass the selected annotation if the cell is open to prevent unnecessary re-renders
  const optimizedSelectedAnnotationId = useMemo(
    () => (openMarkerDetailsCell === cellId ? selectedAnnotationId : undefined),
    [cellId, openMarkerDetailsCell, selectedAnnotationId],
  )

  const openMarkersDialog = useCallback(() => {
    onOpenInLineThread?.()
  }, [onOpenInLineThread])

  const selectThread = useStableCallback(
    (threadId: string, opts: {skipLineSelection?: boolean} = {skipLineSelection: false}) => {
      selectThreadId(threadId)
      openMarkersDialog()
      if (opts.skipLineSelection) return
      // select the line(s) the comment was made on
      const thread = threads.find(t => t.id === threadId)
      if (thread && thread.diffSide && thread.line) {
        const startLine = thread.startLine ?? thread.line
        const startDiffSide = thread.startDiffSide ?? thread.diffSide
        replaceSelectedDiffRowRange({
          diffAnchor: fileAnchor,
          endLineNumber: thread.line,
          endOrientation: thread.diffSide === 'LEFT' ? 'left' : 'right',
          startLineNumber: startLine,
          startOrientation: startDiffSide === 'LEFT' ? 'left' : 'right',
          firstSelectedLineNumber: startLine,
          firstSelectedOrientation: startDiffSide === 'LEFT' ? 'left' : 'right',
        })
      }
    },
  )

  const selectAnnotation = useStableCallback(
    (annotationId: string, opts: {skipLineSelection?: boolean} = {skipLineSelection: false}) => {
      selectAnnotationId(annotationId)
      openMarkersDialog()

      if (opts.skipLineSelection) return

      // select the line(s) the annotation was made on
      const annotation = annotations.find(a => a.id === annotationId)
      if (annotation) {
        replaceSelectedDiffRowRange({
          diffAnchor: fileAnchor,
          endLineNumber: annotation.endLine,
          endOrientation: 'right',
          startLineNumber: annotation.startLine,
          startOrientation: 'right',
          firstSelectedLineNumber: annotation.startLine,
          firstSelectedOrientation: 'right',
        })
      }
    },
  )

  const closeMarkerListDialog = useCallback(() => {
    closeDialog('marker-list')
  }, [closeDialog])

  return {
    // New conversation
    isNewConversationDialogOpen,
    startNewConversation,
    closeNewConversation,
    startNewConversationWithSuggestedChange,
    shouldStartNewConversationWithSuggestedChange,

    // Context menus
    isContextMenuOpen,
    openContextMenu,
    openContextMenuFromActionBar,
    closeContextMenu,
    toggleContextMenu,
    toggleContextMenuFromActionBar,

    optimizedSelectedThreadId,
    optimizedSelectedAnnotationId,
    selectThread,
    selectAnnotation,
    openMarkersDialog,
    closeMarkerListDialog,
    annotations,
    returnFocusRef,
    threads,
    anyMenuOpen,
  }
}
