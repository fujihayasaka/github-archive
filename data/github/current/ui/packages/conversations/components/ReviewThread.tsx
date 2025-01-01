import {CompactCommentButton} from '@github-ui/commenting/CompactCommentButton'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {useAnalytics} from '@github-ui/use-analytics'
import {Box} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useRef, useState} from 'react'

import {anchorComment} from '../helpers'
import {generateSuggestedChangeLineRangeFromDiffThread} from '../suggested-changes'
import type {CommentAuthor, Thread} from '../types'
import type {AddCommentEditorProps} from './AddCommentEditor'
import {AddCommentEditor} from './AddCommentEditor'
import {ReviewThreadComment, type ReviewThreadCommentProps} from './ReviewThreadComment'
import {StaticUnifiedDiffPreview} from './StaticUnifiedDiffPreview'

export interface ReviewThreadProps
  extends Pick<
      ReviewThreadCommentProps,
      'commentingImplementation' | 'repositoryId' | 'subjectId' | 'subject' | 'viewerData'
    >,
    Pick<AddCommentEditorProps, 'batchingEnabled' | 'batchPending' | 'suggestedChangesConfig'> {
  commentAnchorPrefix?: string
  commentsConnectionId?: string
  filePath: string
  hideDiffPreview?: boolean
  isInlineComment: boolean
  enterDialogMode?: (shouldFocusStartCommentButton?: boolean) => void
  onRefreshThread?: (threadId: string) => void
  tabSize?: number
  thread: Thread
  threadPositionNumber?: number
  threadsConnectionId?: string
  shouldLimitHeight?: boolean
  ghostUser?: CommentAuthor
}

/**
 * Renders a given review thread's comments along with a reply comment box.
 *
 * TODO:
 * - Support paginated loading of large review threads.
 * - Better support for deleted comment authors.
 */
export function ReviewThread({
  batchingEnabled,
  batchPending,
  commentAnchorPrefix,
  commentingImplementation,
  commentsConnectionId,
  filePath,
  hideDiffPreview,
  isInlineComment,
  onRefreshThread,
  enterDialogMode,
  repositoryId,
  subject,
  subjectId,
  tabSize,
  thread,
  threadPositionNumber,
  threadsConnectionId,
  shouldLimitHeight = true,
  suggestedChangesConfig,
  viewerData,
  ghostUser,
}: ReviewThreadProps) {
  const [isReplying, setIsReplying] = useState(false)
  const [quoteReplyText, setQuoteReplyText] = useState<string | undefined>(undefined)
  const {sendAnalyticsEvent} = useAnalytics()
  const {addThreadReply} = commentingImplementation
  const replyButtonRef = useRef<HTMLButtonElement>(null)

  const addReplyComment = ({
    commentText,
    onCompleted,
    onError,
    submitBatch,
  }: {
    commentText: string
    onCompleted?: (commentDatabaseId?: number) => void
    onError: (error: Error) => void
    submitBatch?: boolean
  }) => {
    const commentsConnectionIds = []
    if (thread.commentsData.__id) commentsConnectionIds.push(thread.commentsData.__id)
    if (commentsConnectionId) commentsConnectionIds.push(commentsConnectionId)

    const handleCompleted = (commentDatabaseId?: number) => {
      if (commentDatabaseId) anchorComment(commentDatabaseId.toString())
      onCompleted?.()
      onRefreshThread?.(thread.id)
    }

    addThreadReply({
      commentsConnectionIds,
      filePath,
      thread,
      text: commentText,
      submitBatch,
      onCompleted: handleCompleted,
      onError,
      threadsConnectionId,
    })
    sendAnalyticsEvent('comments.add', 'ADD_COMMENT_BUTTON')
  }

  const cancelComment = () => {
    setIsReplying(false)
    sendAnalyticsEvent('comments.cancel_thread_reply', 'CANCEL_REVIEW_THREAD_BUTTON')
    ssrSafeWindow?.requestAnimationFrame(() => replyButtonRef.current?.focus())
  }

  const onQuoteReply = (text?: string) => {
    setQuoteReplyText(text)
    setIsReplying(true)
  }

  if (thread.commentsData.comments === null || thread.commentsData.comments.length < 1) return null
  const lineRange = generateSuggestedChangeLineRangeFromDiffThread(thread)
  const applySuggestedChangesValidationData =
    thread.subjectType === 'LINE'
      ? {
          lineRange,
        }
      : undefined

  return (
    <div data-testid="review-thread">
      <Box sx={shouldLimitHeight ? {maxHeight: '40vh', overflowY: 'auto'} : {}}>
        {/**
         * We always render StaticUnifiedDiffPreview for threads in Activity View above the ReviewThread component.
         * This additional check will prevent 2 of them being rendered on outdated review threads
         * TODO: maybe we can move the rendering of this to be in the ReviewDialog component to avoid conditional logic in a future PR?
         * */}
        {!hideDiffPreview && thread.isOutdated && (
          <StaticUnifiedDiffPreview subject={thread.subject} tabSize={tabSize ?? 4} />
        )}
        {thread.commentsData.comments.map((comment, index) => {
          return (
            <ReviewThreadComment
              enterDialogMode={enterDialogMode}
              isAnchorable
              index={index}
              threadPositionNumber={threadPositionNumber}
              isFirstComment={index === 0}
              isInlineComment={isInlineComment}
              isLastChild={index === thread.commentsData.comments.length - 1}
              key={comment.id}
              anchorPrefix={commentAnchorPrefix}
              comment={comment}
              commentConnectionId={thread.commentsData.__id}
              commentingImplementation={commentingImplementation}
              filePath={filePath}
              isOutdated={thread.isOutdated}
              repositoryId={repositoryId}
              subject={subject}
              subjectId={subjectId}
              threadId={thread.id}
              onRefreshThread={onRefreshThread}
              onQuoteReply={onQuoteReply}
              threadCommentCount={thread.commentsData.comments.length}
              threadsConnectionId={threadsConnectionId}
              isThreadResolved={!!thread.isResolved}
              suggestedChangesConfig={suggestedChangesConfig}
              applySuggestedChangesValidationData={applySuggestedChangesValidationData}
              viewerData={viewerData}
              ghostUser={ghostUser}
            />
          )
        })}
        {thread.reviewCommentsLimitExceeded && (
          <Banner
            aria-label="Warning"
            title="Warning"
            variant="warning"
            hideTitle
            description={`Only the first ${(thread.reviewCommentsLimit || 0) - 1} replies are currently being shown.`}
            className="m-3"
          />
        )}
        {thread.viewerCanReply && (
          <Box
            sx={{
              borderBottomLeftRadius: 2,
              borderBottomRightRadius: 2,
              p: 2,
            }}
          >
            {isReplying && (
              <AddCommentEditor
                batchingEnabled={batchingEnabled}
                batchPending={batchPending}
                commentBoxConfig={commentingImplementation.commentBoxConfig}
                commentBoxSubject={commentingImplementation.commentBoxSubject}
                condensed={false}
                fileLevelComment
                filePath={filePath}
                focusOnMount
                isReplying
                onCancelComment={cancelComment}
                repositoryId={repositoryId}
                quotedText={quoteReplyText}
                subjectId={subjectId}
                threadId={thread.id}
                onAddComment={addReplyComment}
                suggestedChangesConfig={suggestedChangesConfig}
              />
            )}
            {!isReplying && (
              <CompactCommentButton
                ref={replyButtonRef}
                onClick={() => {
                  sendAnalyticsEvent('comments.start_thread_reply', 'REPLY_TO_THREAD_INPUT_BUTTON')
                  setIsReplying(true)
                }}
              >
                Write a reply
              </CompactCommentButton>
            )}
          </Box>
        )}
      </Box>
    </div>
  )
}
