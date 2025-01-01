import {ensurePreviousActiveDialogIsClosed} from '@github-ui/conversations/ensure-previous-active-dialog-is-closed'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {CommentDiscussionIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {useRef, useState} from 'react'

import {CommentsSidePanel} from './CommentsSidePanel'
import type {PullRequest} from '../page-data/payloads/toolbar'
import {useThreadPreviewsPageData, type ThreadPreviewsPayload} from '../page-data/payloads/thread-previews'

export interface OpenCommentsSidePanelButtonProps {
  tabSize?: number
  pullRequest: PullRequest
  repositoryId: number
  threadPreviews: ThreadPreviewsPayload
}

/**
 * Renders a button that opens the comments side panel
 */
export function OpenCommentsSidePanelButton({
  pullRequest,
  repositoryId,
  tabSize,
  ...rest
}: OpenCommentsSidePanelButtonProps) {
  const [commentsSidePanelIsOpen, setCommentsSidePanelIsOpen] = useState(false)
  const toggleSidePanelRef = useRef<HTMLButtonElement>(null)

  const pullRequestId = pullRequest.id

  const {data: threadPreviews} = useThreadPreviewsPageData({
    pathName: pullRequest.pathName,
    initialData: rest.threadPreviews,
  })

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
          count={threadPreviews.length || undefined}
          leadingVisual={CommentDiscussionIcon}
          size="small"
          onClick={() => {
            ensurePreviousActiveDialogIsClosed()
            setCommentsSidePanelIsOpen(true)
          }}
        />
        <CommentsSidePanel
          isOpen={commentsSidePanelIsOpen}
          pullRequestId={pullRequestId}
          repositoryId={repositoryId.toString()}
          tabSize={tabSize}
          threadPreviews={threadPreviews}
          toggleSidesheetRef={toggleSidePanelRef}
          onClose={() => setCommentsSidePanelIsOpen(false)}
        />
      </ErrorBoundary>
    </div>
  )
}
