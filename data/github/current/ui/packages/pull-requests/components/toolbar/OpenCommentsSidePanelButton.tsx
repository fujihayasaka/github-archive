import {ensurePreviousActiveDialogIsClosed} from '@github-ui/conversations/ensure-previous-active-dialog-is-closed'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {CommentDiscussionIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {useRef, useState} from 'react'

import {CommentsSidePanel} from './CommentsSidePanel'
import type {PullRequest} from '../../page-data/payloads/toolbar'
import {useThreadPreviewsPageData, type ThreadPreviewsPayload} from '../../page-data/payloads/thread-previews'
import type {CommentingImplementation} from '@github-ui/conversations'
import {useCommentCountFromMarkersData} from '../../page-data/loaders/use-markers-data'
import type {PageLimits} from '../../page-data/payloads/files'

export interface OpenCommentsSidePanelButtonProps {
  commentBoxConfig: CommentingImplementation['commentBoxConfig']
  tabSize?: number
  pageLimits: PageLimits
  pullRequest: PullRequest
  repositoryId: number
  threadPreviews: ThreadPreviewsPayload
}

/**
 * Renders a button that opens the comments side panel
 */
export function OpenCommentsSidePanelButton({
  commentBoxConfig,
  pageLimits,
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

  const {data: diffCommentCount} = useCommentCountFromMarkersData({basePath: pullRequest.pathName})

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
          count={diffCommentCount}
          leadingVisual={CommentDiscussionIcon}
          size="small"
          onClick={() => {
            ensurePreviousActiveDialogIsClosed()
            setCommentsSidePanelIsOpen(true)
          }}
        >
          <span className="d-none d-xl-block">Comments</span>
        </Button>
        <CommentsSidePanel
          commentBoxConfig={commentBoxConfig}
          isOpen={commentsSidePanelIsOpen}
          pageLimits={pageLimits}
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
