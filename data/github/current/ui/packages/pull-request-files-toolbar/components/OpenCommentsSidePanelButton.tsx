import {ensurePreviousActiveDialogIsClosed} from '@github-ui/conversations/ensure-previous-active-dialog-is-closed'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {CommentDiscussionIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {useRef, useState} from 'react'

import {CommentsSidePanel} from './CommentsSidePanel'
import type {ThreadPreviewsPayload} from '../page-data/payloads/thread-previews'

export interface OpenCommentsSidePanelButtonProps {
  pullRequestId: string
  repositoryId: string
  tabSize?: number
  threadPreviews: ThreadPreviewsPayload
}

/**
 * Renders a button that opens the comments side panel
 */
export function OpenCommentsSidePanelButton({
  pullRequestId,
  repositoryId,
  tabSize,
  threadPreviews,
}: OpenCommentsSidePanelButtonProps) {
  const [commentsSidePanelIsOpen, setCommentsSidePanelIsOpen] = useState(false)
  const toggleSidePanelRef = useRef<HTMLButtonElement>(null)

  return (
    <div className="d-flex flex-items-center">
      <ErrorBoundary
        fallback={
          <Button
            aria-label="The comments side panel cannot currently be opened."
            leadingVisual={CommentDiscussionIcon}
            size="small"
            variant="invisible"
          />
        }
      >
        <Button
          ref={toggleSidePanelRef}
          aria-label="Open comments side panel"
          leadingVisual={CommentDiscussionIcon}
          size="small"
          variant="invisible"
          onClick={() => {
            ensurePreviousActiveDialogIsClosed()
            setCommentsSidePanelIsOpen(true)
          }}
        />
        <CommentsSidePanel
          isOpen={commentsSidePanelIsOpen}
          pullRequestId={pullRequestId}
          repositoryId={repositoryId}
          tabSize={tabSize}
          threadPreviews={threadPreviews}
          toggleSidesheetRef={toggleSidePanelRef}
          onClose={() => setCommentsSidePanelIsOpen(false)}
        />
      </ErrorBoundary>
    </div>
  )
}
