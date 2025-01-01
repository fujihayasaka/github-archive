import type {CommentingImplementation, Thread, Comment, SuggestedChange} from '@github-ui/conversations'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {useCallback, useMemo} from 'react'
import {pullRequestMarkersKey, type Markers} from '../page-data/loaders/use-markers-data'
import {useResolveThreadMutation} from '../mutations/use-resolve-thread-mutation'
import {useUnresolveThreadMutation} from '../mutations/use-unresolve-thread-mutation'
import {useUpdateReviewCommentMutation} from '../mutations/use-update-review-comment-mutation'
import {useDeleteReviewCommentMutation} from '../mutations/use-delete-review-comment-mutation'
import {useHideCommentMutation} from '../mutations/use-hide-comment-mutation'
import {useUnhideCommentMutation} from '../mutations/use-unhide-comment-mutation'
import {useCreateReviewCommentMutation} from '../mutations/use-create-review-comment-mutation'
import {useCreateReplyCommentMutation} from '../mutations/use-create-reply-comment-mutation'
import type {DiffLine, LineRange} from '@github-ui/diff-lines'
import {isContextDiffLine} from '@github-ui/diff-lines/line-helpers'
import type {ReactionContent} from '@github-ui/reaction-viewer/ReactionGroupsUtils'
import {useReactToCommentMutation} from '../mutations/use-react-to-comment-mutation'
import {useSelectedRefContext} from '../contexts/SelectedRefContext'
import {useSubmitSuggestedChangesMutation} from '../mutations/use-submit-suggested-changes-mutation'
import type {RepoSubject} from '@github-ui/comment-box/subject'
import {useBlockUserFromOrgMutation} from '../mutations/use-block-user-from-org-mutation'
import {useUnblockUserFromOrgMutation} from '../mutations/use-unblock-user-from-org-mutation'

/**
 * Returns a commenting implementation for the pull request experience
 *
 * This will continue to be fleshed out as part of the 19.4 files changed staff ship
 */
export function usePullRequestCommenting(
  pullRequestPathName: string,
  commentBoxConfig: CommentingImplementation['commentBoxConfig'],
  currentOid: string,
  commentBoxSubject?: RepoSubject,
): CommentingImplementation {
  const {endOid, startOid} = useSelectedRefContext()

  const fetchThread = useCallback(
    // Relay expects a global relay id for the thread, but we are now using database ids
    async (threadId: string) => {
      return new Promise<Thread | undefined>(async resolve => {
        const queryClient = getQueryClient()
        const markers = queryClient.getQueryData<Markers>(pullRequestMarkersKey(pullRequestPathName))

        // For staff ship, we are not handling async fetching of threads from the server
        const thread = markers?.threads?.[Number(threadId)]
        resolve(thread)
      })
    },
    [pullRequestPathName],
  )
  const {mutate} = useCreateReviewCommentMutation(pullRequestPathName)
  const addThread = useCallback(
    ({
      text,
      diffLine,
      isLeftSide,
      isLineSelected,
      filePath,
      onCompleted,
      selectedDiffRowRange,
      submitBatch,
      onError,
    }: {
      text: string
      diffLine?: DiffLine
      filePath: string
      isLeftSide?: boolean
      isLineSelected?: boolean
      onCompleted?: (threadId: string, commentDatabaseId?: number) => void
      onError?: (error: Error) => void
      selectedDiffRowRange?: LineRange
      submitBatch?: boolean
    }) => {
      if (!diffLine) return
      const isMultiLineComment: boolean =
        selectedDiffRowRange && selectedDiffRowRange.startLineNumber !== selectedDiffRowRange.endLineNumber
          ? true
          : false
      let line: number = diffLine.blobLineNumber
      let side: 'left' | 'right' = isLeftSide && !isContextDiffLine(diffLine) ? 'left' : 'right'
      let startLine: number | undefined
      let startSide: 'left' | 'right' | undefined

      if (selectedDiffRowRange && isMultiLineComment && isLineSelected) {
        side = selectedDiffRowRange.endOrientation === 'left' ? 'left' : 'right'
        startSide = selectedDiffRowRange.startOrientation === 'left' ? 'left' : 'right'
        line = selectedDiffRowRange.endLineNumber
        startLine = selectedDiffRowRange.startLineNumber
      }
      mutate(
        {
          text,
          line,
          path: filePath,
          side,
          startSide,
          submitBatch,
          startLine,
          comparisonEndOid: endOid,
          comparisonStartOid: startOid,
        },

        {
          onError,
          onSuccess: data =>
            data.comment.databaseId
              ? onCompleted?.(data.thread.id, data.comment.databaseId)
              : onCompleted?.(data.thread.id),
        },
      )
    },
    [endOid, mutate, startOid],
  )

  const {mutate: hideCommentMutation} = useHideCommentMutation(pullRequestPathName)
  const hideComment = useCallback(
    async (args: {
      commentDatabaseId: number | null | undefined
      reason: string
      onCompleted?: () => void
      onError: (error: Error) => void
    }) => {
      if (!args.commentDatabaseId) throw new Error('Comment not found')

      hideCommentMutation(
        {commentDatabaseId: args.commentDatabaseId, reason: args.reason},
        {onError: args.onError, onSuccess: args.onCompleted},
      )
    },
    [hideCommentMutation],
  )

  const {mutate: unhideCommentMutation} = useUnhideCommentMutation(pullRequestPathName)
  const unhideComment = useCallback(
    async (args: {
      commentDatabaseId: number | null | undefined
      onCompleted?: () => void
      onError: (error: Error) => void
    }) => {
      if (!args.commentDatabaseId) throw new Error('Comment not found')

      unhideCommentMutation(
        {commentDatabaseId: args.commentDatabaseId},
        {onError: args.onError, onSuccess: args.onCompleted},
      )
    },
    [unhideCommentMutation],
  )
  const {mutate: resolveThreadMutation} = useResolveThreadMutation(pullRequestPathName)
  const resolveThread = useCallback(
    async (args: {onCompleted?: () => void; onError: (error: Error) => void; threadId: string}) => {
      resolveThreadMutation({threadId: args.threadId}, {onError: args.onError, onSuccess: args.onCompleted})
    },
    [resolveThreadMutation],
  )

  const {mutate: unresolveThreadMutation} = useUnresolveThreadMutation(pullRequestPathName)
  const unresolveThread = useCallback(
    async (args: {onCompleted?: () => void; onError: (error: Error) => void; threadId: string}) => {
      unresolveThreadMutation({threadId: args.threadId}, {onError: args.onError, onSuccess: args.onCompleted})
    },
    [unresolveThreadMutation],
  )

  const {mutate: updateComment} = useUpdateReviewCommentMutation(pullRequestPathName)
  const editComment = useCallback(
    async ({
      comment,
      text,
      onError,
      onCompleted,
    }: {
      comment: Comment
      text: string
      onError: (error: Error) => void
      onCompleted?: () => void
    }) => {
      updateComment(
        {commentId: String(comment.databaseId), body: text, bodyVersion: comment.bodyVersion},
        {onError, onSuccess: onCompleted},
      )
    },
    [updateComment],
  )

  const {mutate: deleteCommentMutation} = useDeleteReviewCommentMutation(pullRequestPathName)
  const deleteComment = useCallback(
    async ({
      commentId,
      threadId,
      filePath,
      onCompleted,
      onError,
    }: {
      commentId: string // relay id
      filePath: string
      onCompleted?: () => void
      onError: (error: Error) => void
      threadCommentCount?: number
      threadsConnectionId?: string
      threadId: string
    }) => {
      deleteCommentMutation({commentId, threadId, filePath}, {onError, onSuccess: onCompleted})
    },
    [deleteCommentMutation],
  )
  const {mutate: addReply} = useCreateReplyCommentMutation(pullRequestPathName)
  const addThreadReply = useCallback(
    ({
      onCompleted,
      onError,
      thread,
      text,
      submitBatch,
      filePath,
    }: {
      onCompleted?: (commentDatabaseId?: number) => void
      onError: (error: Error) => void
      submitBatch?: boolean
      text: string
      thread: Thread
      filePath: string
    }) => {
      const lastComment = thread.commentsData.comments[thread.commentsData.comments.length - 1]
      const inReplyTo = lastComment?.databaseId
      addReply(
        {
          text,
          submitBatch,
          inReplyTo,
          path: filePath,
          comparisonEndOid: endOid,
          comparisonStartOid: startOid,
        },

        {
          onError,
          onSuccess: data => (data.comment.databaseId ? onCompleted?.(data.comment.databaseId) : onCompleted?.()),
        },
      )
    },
    [addReply, endOid, startOid],
  )

  const {mutate: submitSuggestions} = useSubmitSuggestedChangesMutation(pullRequestPathName)
  const submitSuggestedChanges = useCallback(
    (args: {
      commitMessage: string
      suggestedChanges: SuggestedChange[]
      onError: (error: Error, type?: string, friendlyMessage?: string) => void
      onCompleted?: () => void
    }) => {
      submitSuggestions(
        {changes: args.suggestedChanges, message: args.commitMessage, currentOid},
        {
          onSuccess: args.onCompleted,
          onError: (error: Error) => {
            args.onError(error, 'submitSuggestedChanges', 'Failed to submit suggested changes')
          },
        },
      )
    },
    [currentOid, submitSuggestions],
  )

  const {mutate: reactToCommentMutation} = useReactToCommentMutation(pullRequestPathName)
  const reactToComment = useCallback(
    (args: {
      commentDatabaseId: number | null | undefined
      threadId: string
      reaction: ReactionContent
      viewerHasReacted: boolean
      onCompleted?: () => void
      onError: (error: Error) => void
    }) => {
      if (!args.commentDatabaseId) throw new Error('Comment not found')

      reactToCommentMutation(
        {
          commentDatabaseId: args.commentDatabaseId,
          threadId: args.threadId,
          reaction: args.reaction,
          viewerHasReacted: args.viewerHasReacted,
        },
        {onError: args.onError, onSuccess: args.onCompleted},
      )
    },
    [reactToCommentMutation],
  )

  const {mutate: blockUserFromOrgMutation} = useBlockUserFromOrgMutation(pullRequestPathName)
  const blockUserFromOrg = useCallback(
    async (args: {
      duration: string
      hiddenReason: string | undefined
      notifyBlockedUser: boolean
      organizationLogin: string
      shouldHideComment: boolean
      userLogin: string
      onCompleted?: () => void
      onError: (error: Error) => void
    }) => {
      blockUserFromOrgMutation(
        {
          duration: args.duration,
          hiddenReason: args.hiddenReason,
          organizationLogin: args.organizationLogin,
          notifyBlockedUser: args.notifyBlockedUser,
          shouldHideComment: args.shouldHideComment,
          userLogin: args.userLogin,
        },
        {
          onError: args.onError,
          onSuccess: args.onCompleted,
        },
      )
    },
    [blockUserFromOrgMutation],
  )

  const {mutate: unblockUserFromOrgMutation} = useUnblockUserFromOrgMutation(pullRequestPathName)
  const unblockUserFromOrg = useCallback(
    async (args: {
      organizationLogin: string
      userLogin: string
      onCompleted?: () => void
      onError: (error: Error) => void
    }) => {
      unblockUserFromOrgMutation(
        {organizationLogin: args.organizationLogin, userLogin: args.userLogin},
        {onError: args.onError, onSuccess: args.onCompleted},
      )
    },
    [unblockUserFromOrgMutation],
  )

  const shouldRefetchThread = useCallback(
    (currentThread: Thread) => {
      // Get the thread
      const queryClient = getQueryClient()
      const markers = queryClient.getQueryData<Markers>(pullRequestMarkersKey(pullRequestPathName))
      const thread = markers?.threads?.[Number(currentThread.id)]

      // Compare resolved status which can be mismatched by resolving in the comments panel
      return thread?.isResolved !== currentThread.isResolved
    },
    [pullRequestPathName],
  )

  return useMemo(() => {
    return {
      addThread,
      addThreadReply,
      blockUserFromOrg,
      unblockUserFromOrg,
      commentBoxConfig,
      commentBoxSubject,
      editComment,
      deleteComment,
      fetchThread,
      lazyFetchReactionGroups: true,
      reactToComment,
      resolveThread,
      resolvingEnabled: true,
      suggestedChangesEnabled: true,
      unresolveThread,
      batchingEnabled: true,
      hideComment,
      unhideComment,
      shouldRefetchThread,
      submitSuggestedChanges,
      // Everything after this needs to be updated/filled out. If you update one, please move it above this line
      multilineEnabled: false,
      pendingSuggestedChangesBatch: [],
      addSuggestedChangeToPendingBatch: () => {},
      removeSuggestedChangeFromPendingBatch: () => {},
      addFileLevelThread: () => {},
    }
  }, [
    addThread,
    addThreadReply,
    blockUserFromOrg,
    unblockUserFromOrg,
    commentBoxConfig,
    commentBoxSubject,
    editComment,
    deleteComment,
    fetchThread,
    reactToComment,
    resolveThread,
    unresolveThread,
    hideComment,
    unhideComment,
    shouldRefetchThread,
    submitSuggestedChanges,
  ])
}
