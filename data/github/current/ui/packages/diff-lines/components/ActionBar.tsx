import {PlusIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, ButtonGroup, IconButton, useRefObjectAsForwardedRef} from '@primer/react'
import type {RefObject} from 'react'
import {forwardRef, useCallback, useRef} from 'react'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

import {useDiffContext} from '../contexts/DiffContext'
import {useDiffLineContext} from '../contexts/DiffLineContext'
import {useActionBarDialogs} from '../hooks/use-action-bar-dialogs'
import {useActionBarFocus} from '../hooks/use-action-bar-focus'
import type {DiffLine, FileDiffReference} from '../types'
import CommentIndicator from './CommentIndicator'
import {CellContextMenu} from './DiffLineTableCellContextMenus'
import {InProgressCommentIndicator} from './InProgressCommentIndicator'
import styles from './ActionBar.module.css'
import {clsx} from 'clsx'
import {CommentsPreference} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'

/**
 * The ActionBar is a set of buttons that appears on hover or focus of a cell in the diff grid.
 * The buttons will be absolutely positioned to the right side of the diff cell.
 */
type ActionBarProps = {
  authorLogin: string
  authorAvatarUrl: string
  cellRef: RefObject<HTMLTableCellElement>
  showStartConversation: boolean
  cellId?: string
  hasDraftComment?: boolean
  copilotChatReference?: FileDiffReference
  shouldDisplayCollapseComments?: boolean
  onOpenInLineThread?: () => void
}

export const ActionBar = forwardRef(function ActionBar(
  {
    authorAvatarUrl,
    authorLogin,
    cellId,
    cellRef,
    showStartConversation,
    hasDraftComment,
    copilotChatReference,
    onOpenInLineThread,
    shouldDisplayCollapseComments,
  }: ActionBarProps,
  dialogReturnFocusRef: React.ForwardedRef<HTMLButtonElement>,
) {
  const viewConversationButtonRef = useRef<HTMLButtonElement>(null)
  const startConversationButtonRef = useRef<HTMLButtonElement>(null)
  const {
    commentingEnabled,
    viewerData: {lineSpacingPreference, commentsPreference},
  } = useDiffContext()
  const {diffLine, isRowSelected} = useDiffLineContext()
  const line = diffLine as DiffLine

  const contextMenuRef = useRef<HTMLButtonElement>(null)

  // When there are no markers, return focus back to start conversation button
  // eslint-disable-next-line react-compiler/react-compiler
  const returnFocusToRef = viewConversationButtonRef.current ? viewConversationButtonRef : startConversationButtonRef

  useRefObjectAsForwardedRef(dialogReturnFocusRef, returnFocusToRef)
  const {diff_inline_comments: diffInlineCommentsFeatureIsEnabled} = useFeatureFlags()

  const totalCommentsCount = line.threadsData?.totalCommentsCount || 0
  const totalAnnotationsCount = line.annotationsData?.totalCount || 0
  const totalCommentsAndAnnotationsCount = totalCommentsCount + totalAnnotationsCount

  const hasThreads = totalCommentsAndAnnotationsCount > 0

  const {isActionBarFocused, handleActionBarBlur, handleActionBarFocusCapture, handleActionBarKeydownCapture} =
    useActionBarFocus({cellRef})

  const {
    annotations,
    isContextMenuOpen,
    openMarkerOrListDialogFromActionBar,
    startNewConversationFromActionBar,
    startNewConversationFromActionBarWithSuggestedChange,
    anyMenuOpen,
    threads,
    toggleContextMenu,
    toggleContextMenuFromActionBar,
  } = useActionBarDialogs({
    cellId,
    actionBarRef: contextMenuRef,
    onOpenInLineThread,
  })

  const handleActionBarClick = useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      if (isRowSelected) e.preventDefault()
    },
    [isRowSelected],
  )

  const viewConversations =
    commentingEnabled &&
    hasThreads &&
    (!diffInlineCommentsFeatureIsEnabled || commentsPreference === CommentsPreference.Collapsed)

  const startConversation = commentingEnabled && showStartConversation

  return (
    <div aria-hidden={!isActionBarFocused} className={clsx('d-flex', 'flex-row', styles['action-bar-position'])}>
      <ButtonGroup
        onBlur={handleActionBarBlur}
        onClick={handleActionBarClick}
        onFocusCapture={handleActionBarFocusCapture}
        onKeyDownCapture={handleActionBarKeydownCapture}
        className={styles['action-bar-button-group']}
      >
        {viewConversations && (
          <Button
            ref={viewConversationButtonRef}
            aria-expanded={anyMenuOpen}
            aria-label="View conversations"
            size="small"
            className={clsx('py-0', 'px-1', styles.actionBarHeight)}
            onClick={event => {
              // if there's a single thread or annotation, prevent default so we don't select the cell.
              // we'll let the conversation selection logic handle selecting the cell(s) associated to the comment.
              if (threads.length === 1 || annotations.length === 1) {
                event.preventDefault()
              }

              openMarkerOrListDialogFromActionBar()
            }}
          >
            <CommentIndicator lineSpacingPreference={lineSpacingPreference} />
          </Button>
        )}
        {startConversation && (
          <>
            {hasDraftComment ? (
              <Button
                aria-label="Start conversation (comment in progress)"
                size="small"
                className={clsx('py-0', 'px-1', styles.actionBarHeight, styles.actionBarStartCommentWidth)}
                onClick={startNewConversationFromActionBar}
              >
                <InProgressCommentIndicator
                  lineSpacingPreference={lineSpacingPreference}
                  authorAvatarUrl={authorAvatarUrl}
                  authorLogin={authorLogin}
                />
              </Button>
            ) : (
              // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
              <IconButton
                unsafeDisableTooltip
                aria-label="Start conversation"
                ref={startConversationButtonRef}
                icon={PlusIcon}
                size="small"
                className={clsx('fgColor-muted', styles.actionBarHeight, styles.actionBarStartCommentWidth)}
                onClick={startNewConversationFromActionBar}
              />
            )}
          </>
        )}
        <ActionMenu anchorRef={contextMenuRef} open={isContextMenuOpen} onOpenChange={toggleContextMenu}>
          <ActionMenu.Anchor>
            {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
            <IconButton
              unsafeDisableTooltip
              ref={contextMenuRef}
              aria-haspopup="true"
              aria-label="More actions"
              icon={TriangleDownIcon}
              size="small"
              className={clsx('fgColor-muted', styles.actionBarArrowSizing)}
              onClick={toggleContextMenuFromActionBar}
            />
          </ActionMenu.Anchor>
          <ActionMenu.Overlay width="medium">
            <ActionList>
              <CellContextMenu
                shouldDisplayCollapseComments={shouldDisplayCollapseComments}
                copilotChatReference={copilotChatReference}
                showStartConversation={showStartConversation}
                handleViewMarkersSelection={openMarkerOrListDialogFromActionBar}
                startConversationCurrentLine={startNewConversationFromActionBar}
                startConversationWithSuggestedChange={startNewConversationFromActionBarWithSuggestedChange}
              />
            </ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      </ButtonGroup>
    </div>
  )
})

ActionBar.displayName = 'ActionBar'
