import {PlusIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, ButtonGroup, IconButton, useRefObjectAsForwardedRef} from '@primer/react'
import type {RefObject} from 'react'
import {forwardRef, useRef} from 'react'

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
  handleCopyCode?: () => void
  onOpenInLineThread?: () => void
  toggleViewingMarkers: () => void
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
    handleCopyCode,
    onOpenInLineThread,
    shouldDisplayCollapseComments,
    toggleViewingMarkers,
  }: ActionBarProps,
  dialogReturnFocusRef: React.ForwardedRef<HTMLButtonElement>,
) {
  const viewConversationButtonRef = useRef<HTMLButtonElement>(null)
  const startConversationButtonRef = useRef<HTMLButtonElement>(null)
  const {
    commentingEnabled,
    viewerData: {lineSpacingPreference, commentsPreference},
  } = useDiffContext()
  const {diffLine} = useDiffLineContext()
  const line = diffLine as DiffLine

  const contextMenuRef = useRef<HTMLButtonElement>(null)

  // When there are no markers, return focus back to start conversation button

  const returnFocusToRef = viewConversationButtonRef.current ? viewConversationButtonRef : startConversationButtonRef

  useRefObjectAsForwardedRef(dialogReturnFocusRef, returnFocusToRef)

  const totalCommentsCount = line.threadsData?.totalCommentsCount || 0
  const totalAnnotationsCount = line.annotationsData?.totalCount || 0
  const totalCommentsAndAnnotationsCount = totalCommentsCount + totalAnnotationsCount

  const hasThreads = totalCommentsAndAnnotationsCount > 0

  const {isActionBarFocused, handleActionBarBlur, handleActionBarFocusCapture, handleActionBarKeydownCapture} =
    useActionBarFocus({cellRef})

  const {
    annotations,
    isContextMenuOpen,
    startNewConversation,
    startNewConversationWithSuggestedChange,
    anyMenuOpen,
    threads,
    toggleContextMenu,
    toggleContextMenuFromActionBar,
  } = useActionBarDialogs({
    cellId,
    actionBarRef: contextMenuRef,
    onOpenInLineThread,
  })

  const viewConversations = commentingEnabled && hasThreads && commentsPreference === CommentsPreference.Collapsed

  const shouldShowStartConversation = commentingEnabled && showStartConversation

  const sharedProps = {
    onBlur: handleActionBarBlur,
    onFocusCapture: handleActionBarFocusCapture,
    onKeyDownCapture: handleActionBarKeydownCapture,
  }

  return (
    <>
      {shouldShowStartConversation && (
        <div aria-hidden={!isActionBarFocused} className={clsx('d-flex', 'flex-row', styles['left-action-bar'])}>
          <>
            {hasDraftComment ? (
              <Button
                aria-label="Continue comment in progress"
                size="small"
                className={clsx(
                  'py-0',
                  lineSpacingPreference === 'compact'
                    ? styles['left-action-bar-draft-compact']
                    : styles['left-action-bar-draft-relaxed'],
                  styles.actionBarHeight,
                )}
                onClick={startNewConversation}
                {...sharedProps}
              >
                <InProgressCommentIndicator
                  lineSpacingPreference={lineSpacingPreference}
                  authorAvatarUrl={authorAvatarUrl}
                  authorLogin={authorLogin}
                />
              </Button>
            ) : (
              <IconButton
                icon={PlusIcon}
                aria-label="Add comment"
                ref={startConversationButtonRef}
                size="small"
                className={clsx(
                  'fgColor-muted',
                  'bgColor-accent-emphasis',
                  'fgColor-onEmphasis',
                  'px-0',
                  styles['left-action-bar-new'],
                  styles.actionBarHeight,
                  styles.actionBarStartCommentWidth,
                )}
                onClick={startNewConversation}
                {...sharedProps}
              />
            )}
          </>
        </div>
      )}
      <div aria-hidden={!isActionBarFocused} className={clsx('d-flex', 'flex-row', styles['action-bar-position'])}>
        <ButtonGroup className={styles['action-bar-button-group']} {...sharedProps}>
          {viewConversations && (
            <Button
              ref={viewConversationButtonRef}
              aria-expanded={anyMenuOpen}
              aria-label="View comments"
              size="small"
              className={clsx('py-0', 'px-1', styles.actionBarHeight)}
              onClick={event => {
                // if there's a single thread or annotation, prevent default so we don't select the cell.
                // we'll let the conversation selection logic handle selecting the cell(s) associated to the comment.
                if (threads.length === 1 || annotations.length === 1) {
                  event.preventDefault()
                }

                toggleViewingMarkers?.()
              }}
            >
              <CommentIndicator lineSpacingPreference={lineSpacingPreference} />
            </Button>
          )}

          <ActionMenu anchorRef={contextMenuRef} open={isContextMenuOpen} onOpenChange={toggleContextMenu}>
            <ActionMenu.Anchor>
              <IconButton
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
                  handleCopyCode={handleCopyCode}
                  handleViewMarkersSelection={toggleViewingMarkers}
                  startConversationCurrentLine={startNewConversation}
                  startConversationWithSuggestedChange={startNewConversationWithSuggestedChange}
                />
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </ButtonGroup>
      </div>
    </>
  )
})

ActionBar.displayName = 'ActionBar'
