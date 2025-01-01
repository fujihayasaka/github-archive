import {CopilotDiffChatContextMenu} from '@github-ui/copilot-code-chat/CopilotDiffChatContextMenu'
import type {FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {
  CommentDiscussionIcon,
  CopyIcon,
  FoldDownIcon,
  FoldUpIcon,
  LinkIcon,
  MoveToBottomIcon,
  MoveToTopIcon,
  MultiSelectIcon,
} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {useCallback, type MouseEvent} from 'react'

import {useDiffContext} from '../contexts/DiffContext'
import {useDiffLineContext} from '../contexts/DiffLineContext'
import {useMarkersDialogContext} from '../contexts/MarkersDialogContext'
import {useSelectedDiffRowRangeContext} from '../contexts/SelectedDiffRowRangeContext'
import {threadSummary} from '../helpers/conversation-helpers'
import useExpandHunk from '../hooks/use-expand-hunk'
import type {DiffLine, DiffSide} from '../types'
import {StartConversationContextMenuItems} from './StartConversationContextMenuItems'
import {KeybindingHint} from '@primer/react/experimental'
import {CommentsPreference} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'
import {copyText} from '@github-ui/copy-to-clipboard'
import {anchorLinkForSelection, copilotSelectedDiffLineRange} from '../helpers/line-helpers'
import type {SimpleDiffLine} from '@github-ui/diffs/types'

type CellContextMenuProps = {
  showStartConversation: boolean
  shouldDisplayCollapseComments?: boolean
  copilotChatReference?: FileDiffReference
  handleViewMarkersSelection: (markerLoc?: DiffSide) => void
  startConversationCurrentLine: () => void
  startConversationWithSuggestedChange: () => void
  handleCopyCode?: () => void
}

export function CellContextMenu(props: CellContextMenuProps) {
  return (
    <>
      <MarkerListItems {...props} />
      <CopilotListItems fileDiffReference={props.copilotChatReference} />
      <CopyContentListItems handleCopyCode={props.handleCopyCode} />
      <SelectAllListItem />
      <CopyAnchorLink />
      <HunkListItems />
    </>
  )
}

function CopyAnchorLink() {
  const {diffLine, fileAnchor} = useDiffLineContext()
  const line = diffLine as SimpleDiffLine
  const {selectedDiffRowRange} = useSelectedDiffRowRangeContext()

  const copyAnchorLink = useCallback(() => {
    const link = anchorLinkForSelection({line, range: selectedDiffRowRange, fileAnchor})
    if (link) copyText(link)
  }, [fileAnchor, line, selectedDiffRowRange])

  return (
    <ActionList.Item
      onSelect={copyAnchorLink}
      onMouseDown={(event: MouseEvent) => {
        // We need to prevent the window's Selection object from being reset on mouse down if user has selected text.
        // This is to prevent the browser from resetting the selection before onSelect event callback is called.
        if (window.getSelection()?.toString() !== '') event.preventDefault()
      }}
    >
      <ActionList.LeadingVisual>
        <LinkIcon />
      </ActionList.LeadingVisual>
      Copy link
      <ActionList.TrailingVisual>
        <KeybindingHint keys="Mod+Alt+y" />
      </ActionList.TrailingVisual>
    </ActionList.Item>
  )
}

export function EmptyCellContextMenu() {
  return (
    <>
      <ExpandHunksListItems />
      <SelectAllListItem />
    </>
  )
}

const CopilotListItems: React.FC<{fileDiffReference?: FileDiffReference}> = props => {
  const {selectedDiffRowRange} = useSelectedDiffRowRangeContext()
  const {diffLine, isLeftSide, fileAnchor} = useDiffLineContext()

  const copilotSelectedDiffRowRange = copilotSelectedDiffLineRange(
    selectedDiffRowRange,
    diffLine,
    isLeftSide,
    fileAnchor,
  )

  if (!props.fileDiffReference) return null

  return (
    <CopilotDiffChatContextMenu
      showDivider
      selectedRange={copilotSelectedDiffRowRange}
      fileDiffReference={props.fileDiffReference}
    />
  )
}

function SelectAllListItem() {
  const {fileAnchor} = useDiffLineContext()

  const handleSelectAllSelection = () => {
    // We need to wait one click for the context menu to close before we allow for the event to occur inside of the table instead of context menu
    setTimeout(() => {
      document
        .querySelector(`table[data-diff-anchor="${fileAnchor}"]`)
        ?.dispatchEvent(new KeyboardEvent('keydown', {key: 'a', code: 'KeyA', ctrlKey: true}))
    })
  }

  return (
    <ActionList.Item onSelect={handleSelectAllSelection}>
      <ActionList.LeadingVisual>
        <MultiSelectIcon />
      </ActionList.LeadingVisual>
      Select all
      <ActionList.TrailingVisual>
        <KeybindingHint keys="Mod+a" />
      </ActionList.TrailingVisual>
    </ActionList.Item>
  )
}

function MarkerListItems({
  handleViewMarkersSelection,
  shouldDisplayCollapseComments,
  showStartConversation,
  startConversationCurrentLine,
  startConversationWithSuggestedChange,
}: Omit<CellContextMenuProps, 'copilotChatReference'>) {
  const {commentingEnabled} = useDiffContext()
  const {annotations, threads} = useMarkersDialogContext()
  const hasAnnotations = annotations.length > 0

  if (!commentingEnabled || (!showStartConversation && !threads && !hasAnnotations)) {
    return null
  }

  return (
    <>
      {showStartConversation && (
        <StartConversationContextMenuItems
          handleStartConversation={startConversationCurrentLine}
          handleStartConversationWithSuggestedChange={startConversationWithSuggestedChange}
        />
      )}
      <ViewMarkerListItems
        handleViewMarkersSelection={handleViewMarkersSelection}
        shouldDisplayCollapseComments={shouldDisplayCollapseComments}
      />
      <ActionList.Divider />
    </>
  )
}

function ViewMarkerListItems({
  handleViewMarkersSelection,
  shouldDisplayCollapseComments,
}: {
  handleViewMarkersSelection: (markerLoc?: DiffSide) => void
  shouldDisplayCollapseComments?: boolean
}) {
  const {commentingEnabled} = useDiffContext()
  const {isSplit} = useDiffLineContext()
  const {viewerData} = useDiffContext()

  if (!commentingEnabled || viewerData.commentsPreference === CommentsPreference.Visible) {
    return null
  }

  if (!isSplit) {
    return (
      <UnifiedDiffMarkerListItem
        onSelect={() => handleViewMarkersSelection()}
        shouldDisplayCollapseComments={shouldDisplayCollapseComments}
      />
    )
  }

  return (
    <SplitDiffMarkersListItems
      handleViewMarkersSelection={handleViewMarkersSelection}
      shouldDisplayCollapseComments={shouldDisplayCollapseComments}
    />
  )
}

function SplitDiffMarkersListItems({
  handleViewMarkersSelection,
  shouldDisplayCollapseComments,
}: {
  handleViewMarkersSelection: (markerLoc: DiffSide) => void
  shouldDisplayCollapseComments?: boolean
}) {
  const {originalLineHasThreads, modifiedLineHasThreads, isLeftSide} = useDiffLineContext()
  const {annotations} = useMarkersDialogContext()
  const hasAnnotations = annotations.length > 0
  if (isLeftSide) {
    return (
      <>
        {originalLineHasThreads && (
          <MarkerListItem
            text={shouldDisplayCollapseComments ? 'Collapse comments' : 'Expand comments'}
            onSelect={() => handleViewMarkersSelection('LEFT')}
          />
        )}
        {(modifiedLineHasThreads || hasAnnotations) && (
          <MarkerListItem
            text={shouldDisplayCollapseComments ? 'Collapse comments, modified line' : 'Expand comments, modified line'}
            onSelect={() => handleViewMarkersSelection('RIGHT')}
          />
        )}
      </>
    )
  }

  return (
    <>
      {(modifiedLineHasThreads || hasAnnotations) && (
        <MarkerListItem
          text={shouldDisplayCollapseComments ? 'Collapse comments' : 'Expand comments'}
          onSelect={() => handleViewMarkersSelection('RIGHT')}
        />
      )}
      {originalLineHasThreads && (
        <MarkerListItem
          text={shouldDisplayCollapseComments ? 'Collapse comments, original line' : 'Expand comments, original line'}
          onSelect={() => handleViewMarkersSelection('LEFT')}
        />
      )}
    </>
  )
}

function UnifiedDiffMarkerListItem({
  onSelect,
  shouldDisplayCollapseComments,
}: {
  onSelect: () => void
  shouldDisplayCollapseComments?: boolean
}) {
  const {ghostUser} = useDiffContext()
  const {diffLine} = useDiffLineContext()
  const line = diffLine as DiffLine
  const {annotations} = useMarkersDialogContext()
  const hasMarkers = (line && threadSummary(line.threadsData, ghostUser).length > 0) || annotations.length > 0
  if (!hasMarkers) return null
  return (
    <MarkerListItem
      text={shouldDisplayCollapseComments ? 'Collapse comments' : 'Expand comments'}
      onSelect={() => onSelect()}
    />
  )
}

function MarkerListItem({onSelect, text}: {onSelect: () => void; text: string}) {
  return (
    <ActionList.Item onSelect={onSelect}>
      <ActionList.LeadingVisual>
        <CommentDiscussionIcon />
      </ActionList.LeadingVisual>
      {text}
    </ActionList.Item>
  )
}

function CopyContentListItems({handleCopyCode}: {handleCopyCode?: () => void}) {
  return (
    <ActionList.Item
      onSelect={handleCopyCode}
      onMouseDown={(event: MouseEvent) => {
        // We need to prevent the window's Selection object from being reset on mouse down if user has selected text.
        // This is to prevent the browser from resetting the selection before onSelect event callback is called.
        if (window.getSelection()?.toString() !== '') event.preventDefault()
      }}
    >
      <ActionList.LeadingVisual>
        <CopyIcon />
      </ActionList.LeadingVisual>
      Copy
      <ActionList.TrailingVisual>
        <KeybindingHint keys="Mod+c" />
      </ActionList.TrailingVisual>
    </ActionList.Item>
  )
}

function HunkListItems() {
  const {canExpandStartOfHunk, canExpandEndOfHunk} = useExpandHunk()
  const {previousHunk, nextHunk} = useDiffLineContext()

  if (!canExpandStartOfHunk && !canExpandEndOfHunk && !previousHunk && !nextHunk) return null

  return (
    <>
      <ActionList.Divider />
      <ExpandHunksListItems />
      <JumpToHunkListItems />
    </>
  )
}

function ExpandHunksListItems() {
  const {canExpandStartOfHunk, expandEndOfHunk, expandStartOfHunk, canExpandEndOfHunk} = useExpandHunk()

  return (
    <>
      {canExpandStartOfHunk && (
        <ActionList.Item onSelect={expandStartOfHunk}>
          <ActionList.LeadingVisual>
            <FoldUpIcon />
          </ActionList.LeadingVisual>
          Expand above
        </ActionList.Item>
      )}
      {canExpandEndOfHunk && (
        <ActionList.Item onSelect={expandEndOfHunk}>
          <ActionList.LeadingVisual>
            <FoldDownIcon />
          </ActionList.LeadingVisual>
          Expand below
        </ActionList.Item>
      )}
    </>
  )
}

export function JumpToHunkListItems() {
  const {previousHunk, nextHunk} = useDiffLineContext()
  const {fileAnchor} = useDiffLineContext()

  // We need to ensure these values are not undefined values
  // simply doing a truthy call on these is not adequate as they can return 0, which is falsy in JS
  const hasPreviousHunk = !!previousHunk
  const hasNextHunk = !!nextHunk

  const handleNextHunkSelection = () => {
    // We need to wait one click for the context menu to close before we allow for the event to occur inside of the table instead of context menu
    setTimeout(() => {
      document
        .querySelector(`table[data-diff-anchor="${fileAnchor}"]`)
        ?.dispatchEvent(new KeyboardEvent('keydown', {key: 'PageDown'}))
    })
  }

  const handlePreviousHunkSelection = () => {
    // We need to wait one click for the context menu to close before we allow for the event to occur inside of the table instead of context menu
    setTimeout(() => {
      document
        .querySelector(`table[data-diff-anchor="${fileAnchor}"]`)
        ?.dispatchEvent(new KeyboardEvent('keydown', {key: 'PageUp'}))
    })
  }

  return (
    <>
      {hasNextHunk ? (
        <ActionList.Item aria-keyshortcuts="PageDown" onSelect={handleNextHunkSelection}>
          <ActionList.LeadingVisual>
            <MoveToBottomIcon />
          </ActionList.LeadingVisual>
          Go to next hunk
          <ActionList.TrailingVisual>Page Down</ActionList.TrailingVisual>
        </ActionList.Item>
      ) : null}
      {hasPreviousHunk ? (
        <ActionList.Item aria-keyshortcuts="PageUp" onSelect={handlePreviousHunkSelection}>
          <ActionList.LeadingVisual>
            <MoveToTopIcon />
          </ActionList.LeadingVisual>
          Go to previous hunk
          <ActionList.TrailingVisual>Page Up</ActionList.TrailingVisual>
        </ActionList.Item>
      ) : null}
    </>
  )
}
