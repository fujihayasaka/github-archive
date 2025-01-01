import type {CommentBoxHandle} from '@github-ui/comment-box/CommentBox'
import type {ActivityHeaderHeadingProps} from '@github-ui/commenting/ActivityHeader'
import {ActivityHeader} from '@github-ui/commenting/ActivityHeader'
import {CommentActions} from '@github-ui/commenting/CommentActions'
import {VALUES} from '@github-ui/commenting/Values'
import {noop} from '@github-ui/noop'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {SafeHTMLBox} from '@github-ui/safe-html'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {Box} from '@primer/react'
import {useEffect, useRef, useState} from 'react'

import {anchorComment} from '../helpers'
import type {
  ApplySuggestedChangesValidationData,
  CommentAuthor,
  CommentingImplementation,
  CommentWithoutFragment,
  SuggestedChangesConfiguration,
  ViewerData,
} from '../types'

export interface ReviewThreadCommentWithoutReactionsProps {
  anchorPrefix?: string
  comment: CommentWithoutFragment
  commentConnectionId?: string
  commentingImplementation: CommentingImplementation
  filePath: string
  hideActions?: boolean
  index?: number
  /**
   * If true, the comment will scroll itself into view and show a blue border
   * when the component renders with a hash that matches the comment.
   */
  isAnchorable?: boolean
  isLastChild?: boolean
  onRefreshThread?: (threadId: string) => void
  onQuoteReply?: (quotedText?: string) => void
  enterDialogMode?: (shouldFocusStartCommentButton?: boolean) => void
  repositoryId: string
  suggestedChangesConfig?: SuggestedChangesConfiguration
  applySuggestedChangesValidationData?: ApplySuggestedChangesValidationData
  threadCommentCount?: number
  threadId: string
  threadsConnectionId?: string
  viewerData?: ViewerData
  ghostUser?: CommentAuthor
}

// This is a copy of ReviewThreadComment, slightly modified to remove the Relay dependency
// Eventually the ReviewThreadComment component may be modified to not use Relay anymore,
// at which point it may make sense to switch usage of this component back to ReviewThreadComment.
export function ReviewThreadCommentWithoutReactions({
  isAnchorable = false,
  index = 0,
  isLastChild,
  anchorPrefix = 'r',
  comment,
  commentingImplementation,
  filePath,
  hideActions,
  enterDialogMode = noop,
  onRefreshThread,
  onQuoteReply = noop,
  threadCommentCount,
  threadId,
  threadsConnectionId,
  ghostUser = VALUES.ghostUser,
}: ReviewThreadCommentWithoutReactionsProps): JSX.Element {
  const {addToast} = useToastContext()
  const [isEditing, setIsEditing] = useState(false)
  const [isMinimized, setIsMinimized] = useState(comment.isHidden)
  const [_, setIsSubmitting] = useState(false)
  const {deleteComment, hideComment, unhideComment} = commentingImplementation
  const commentBoxRef = useRef<CommentBoxHandle>(null)
  const commentBodyRef = useRef<HTMLDivElement>(null)

  const focusCommentBox = () => {
    commentBoxRef.current?.focus()
  }

  useEffect(() => {
    if (isEditing) {
      const timeout = window.setTimeout(focusCommentBox)

      return () => {
        window.clearTimeout(timeout)
      }
    }
  }, [isEditing])

  const onDelete = () => {
    deleteComment({
      commentId: comment.id,
      onCompleted: () => {
        onRefreshThread?.(threadId)
      },
      onError: () => {
        setIsSubmitting(false)
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: 'Failed to delete comment',
        })
      },
      threadCommentCount,
      threadId,
      threadsConnectionId,
      filePath,
    })
  }

  const onHide = (reason: string) => {
    hideComment({
      commentId: comment.id,
      reason,
      onCompleted: () => {
        onRefreshThread?.(threadId)
      },
      onError: () => {
        setIsSubmitting(false)
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: 'Failed to hide comment',
        })
      },
    })
  }

  const onUnhide = () => {
    unhideComment({
      commentId: comment.id,
      onCompleted: () => {
        onRefreshThread?.(threadId)
      },
      onError: () => {
        setIsSubmitting(false)
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: 'Failed to unhide comment',
        })
      },
    })
  }

  const onEdit = () => {
    setIsEditing(true)
  }

  // if the hash is `#r42`, this will be `r42`
  const commentId = comment.currentDiffResourcePath?.split('#r').pop()
  const commentAnchor = commentId ? `${anchorPrefix}${commentId}` : undefined
  const commentHref =
    commentAnchor && ssrSafeLocation
      ? new URL(`${ssrSafeLocation.pathname}#${commentAnchor}`, ssrSafeLocation.origin).toString()
      : undefined
  const containerRef = useRef<HTMLDivElement>(null)

  // This mirrors what we do in dotcom currently, see `progressive.ts`. By clicking
  // the link we're able to let the browser apply the `:target` pseudo class to the
  // container and scroll it into view.
  useEffect(() => {
    if (!isAnchorable) return

    if (commentId && commentAnchor && window.location.hash.split('#').pop() === commentAnchor) {
      anchorComment(commentId, anchorPrefix)
      enterDialogMode?.(false)
      containerRef.current?.focus()
    }
  }, [anchorPrefix, commentAnchor, commentId, enterDialogMode, isAnchorable])

  const blueFocusOutlineStyles = {
    outline: `2px solid`,
    outlineColor: 'accent.fg',
    outlineOffset: `-2px`,
    boxShadow: 'none',
  }

  const isReply = index > 0
  const isNestedReply = index > 1

  const comentActivityProps = {
    headingProps: {as: 'h3'} as ActivityHeaderHeadingProps,
    avatarUrl: comment.author?.avatarUrl ?? ghostUser.avatarUrl,
    comment: {
      ...comment,
      url: commentHref ?? '',
      referenceText: comment.reference.text ?? `#${comment.reference.number}`,
    },
    commentRef: containerRef,
    deleteComment: onDelete,
    editComment: onEdit,
    editHistoryComponent: undefined,
    hideComment: onHide,
    onMinimize: setIsMinimized,
    isMinimized,
    commentAuthorLogin: comment.author?.login ?? ghostUser.login,
    navigate: noop,
    commentSubjectAuthorLogin: comment.reference?.author?.login ?? '',
    commentSubjectType: commentingImplementation.commentSubjectType,
    onReplySelect: onQuoteReply,
    unhideComment: onUnhide,
    hideActions,
    isReply,
    forceInlineAvatar: true,
    containerStyle: {},
  }

  return (
    <Box
      ref={containerRef}
      id={isAnchorable ? commentAnchor : undefined}
      tabIndex={-1}
      sx={{
        '&:not(:first-child)': {
          backgroundColor: 'canvas.inset',
        },
        '&:first-child + div': {
          borderTop: '1px solid',
          borderColor: 'border.muted',
        },
        ':target': blueFocusOutlineStyles,
        ':focus': blueFocusOutlineStyles,
        pb: isReply ? 0 : 2,
      }}
    >
      {isNestedReply && (
        <Box sx={{display: 'flex', pl: isReply ? 1 : 0}}>
          <Box
            sx={{
              ml: 4,
              height: 8,
              borderLeft: '1px solid',
              borderColor: 'border.default',
            }}
          />
        </Box>
      )}
      <Box sx={{px: 3, pt: isNestedReply ? 0 : 2, pb: 0}}>
        <ActivityHeader
          {...comentActivityProps}
          actions={hideActions ? undefined : <CommentActions {...comentActivityProps} />}
        />
      </Box>
      <Box sx={{display: 'flex', pl: isReply ? 1 : 0}}>
        {isReply && (
          <Box
            sx={{
              ml: 4,
              mr: 1,
              pl: 3,
              borderLeft: '1px solid',
              borderColor: 'border.default',
              ...(isLastChild && {
                borderImage:
                  'linear-gradient(to bottom, var(--borderColor-default, var(--color-border-default)), rgba(0, 0, 0, 0)) 1 100%',
              }),
            }}
          />
        )}

        {
          <Box sx={isReply ? {pb: 2, pr: 2, overflowX: 'auto', width: '100%'} : {px: 3, pb: 2, width: '100%'}}>
            {comment.bodyHTML && (
              <>
                <SafeHTMLBox
                  ref={commentBodyRef}
                  className="markdown-body"
                  comment-testid={`Comment body html for comment ${comment.id}`}
                  html={comment.bodyHTML as SafeHTMLString}
                  sx={{
                    mt: 1,
                    fontSize: 1,
                  }}
                />
              </>
            )}
          </Box>
        }
      </Box>
    </Box>
  )
}
