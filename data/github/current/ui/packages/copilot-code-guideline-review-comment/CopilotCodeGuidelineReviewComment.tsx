// import type {DiffLine} from '@github-ui/diffs/types'
// import {UnifiedDiffLines} from '@github-ui/diffs/DiffParts'
import {
  ReviewThreadCommentWithoutReactions,
  StaticUnifiedDiffPreview,
  type Comment,
  type CommentingImplementation,
  type Thread,
  type ThreadSubject,
} from '@github-ui/conversations'
import {noop} from '@github-ui/noop'
export interface CopilotCodeGuidelineReviewCommentProps {
  threadSubject: ThreadSubject & {path: string; isResolved: boolean; pullRequestId: string; id: string}
  thread: Thread
  comment: OmitFragment<Comment>
}

export type OmitFragment<T> = Omit<T, ' $fragmentType' | ' $fragmentSpreads'>

export function CopilotCodeGuidelineReviewComment({
  threadSubject,
  thread,
  comment,
}: CopilotCodeGuidelineReviewCommentProps) {
  const commentingImplementation: CommentingImplementation = {
    batchingEnabled: false,
    multilineEnabled: false,
    resolvingEnabled: false,
    pendingSuggestedChangesBatch: [],
    suggestedChangesEnabled: false,
    lazyFetchReactionGroups: false,
    submitSuggestedChanges: noop,
    addSuggestedChangeToPendingBatch: noop,
    removeSuggestedChangeFromPendingBatch: noop,
    addThread: noop,
    addThreadReply: noop,
    addFileLevelThread: noop,
    deleteComment: noop,
    editComment: noop,
    hideComment: noop,
    unhideComment: noop,
    resolveThread: noop,
    unresolveThread: noop,
    fetchThread: async (_threadId: string, _includeAssociatedDiffLines?: boolean) => {
      return thread
    },
    commentBoxConfig: {
      pasteUrlsAsPlainText: false,
      useMonospaceFont: false,
    },
  }
  return (
    <>
      <div className="border borderColor-muted overflox-x-auto">
        <StaticUnifiedDiffPreview tabSize={4} subject={threadSubject} hideHeaderDetails />
      </div>
      {comment && (
        <div>
          <ReviewThreadCommentWithoutReactions
            key={comment.id}
            hideActions
            comment={comment}
            commentingImplementation={commentingImplementation}
            filePath={threadSubject.path}
            repositoryId={comment.repository.id}
            threadId={threadSubject.id}
          />
        </div>
      )}
    </>
  )
}
