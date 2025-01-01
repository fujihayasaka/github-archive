import {StaticUnifiedDiffPreview} from '@github-ui/conversations'
import {SafeHTMLBox} from '@github-ui/safe-html'
import {ChevronRightIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {memo, useCallback, useState} from 'react'
import type {PendingCommentPreview as PendingCommentPreviewType} from '../../page-data/payloads/pending-review'
import {ConversationHeader} from './ConversationHeader'
import {PreviewAuthors} from './PreviewAuthors'

interface PendingCommentPreviewProps {
  commentPreview: PendingCommentPreviewType
  onNavigateToDiffComment: (threadId: string) => void
  tabSize?: number
}

export const PendingCommentPreview = memo(function PendingCommentPreview({
  commentPreview,
  onNavigateToDiffComment,
  tabSize,
}: PendingCommentPreviewProps) {
  const [isCollapsed, setIsCollapsed] = useState(false)

  const navigateToComment = useCallback(() => {
    window.location.hash = `#r${commentPreview.commentId}`
    onNavigateToDiffComment(commentPreview.commentId)
  }, [commentPreview.commentId, onNavigateToDiffComment])

  const previousCommentCount = commentPreview.threadPreviewComments.length
  const previousCommentText = `${previousCommentCount} previous ${previousCommentCount === 1 ? 'comment' : 'comments'}`

  return (
    <div className="border rounded-2 d-flex flex-column">
      <ConversationHeader
        isCollapsed={isCollapsed}
        isOutdated={commentPreview.isOutdated}
        isResolved={commentPreview.isResolved}
        line={commentPreview.line}
        path={commentPreview.path}
        onNavigateToDiffComment={navigateToComment}
        onToggleCollapsed={() => setIsCollapsed(collapsed => !collapsed)}
        threadId={commentPreview.threadId}
      />
      {!isCollapsed && (
        <>
          <div className="border borderColor-muted overflow-x-auto">
            <StaticUnifiedDiffPreview
              diffTableSx={{borderStyle: 'none'}}
              hideHeaderDetails
              subject={commentPreview.subject}
              sx={{m: 0, borderStyle: 'none'}}
              tabSize={tabSize || 4}
            />
          </div>
          {previousCommentCount > 0 && (
            <div className="my-2 px-2">
              <Button
                aria-label="View comment in diff"
                size="small"
                trailingVisual={ChevronRightIcon}
                variant="invisible"
                onClick={navigateToComment}
              >
                <div className="d-flex flex-row flex-justify-start flex-items-center gap-2">
                  <span>{previousCommentText}</span>
                  <PreviewAuthors comments={commentPreview.threadPreviewComments} />
                </div>
              </Button>
            </div>
          )}
          <SafeHTMLBox
            className="markdown-body"
            html={commentPreview.bodyHTML}
            sx={{
              p: 3,
              fontSize: 1,
            }}
          />
        </>
      )}
    </div>
  )
})
