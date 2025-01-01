import {CommentBoxButton, type CommentBoxHandle} from '@github-ui/comment-box/CommentBox'
import type {ActivityHeaderHeadingProps} from '@github-ui/commenting/ActivityHeader'
import {ActivityHeader} from '@github-ui/commenting/ActivityHeader'
import {CommentActions} from '@github-ui/commenting/CommentActions'
import {VALUES} from '@github-ui/commenting/Values'
import {CopilotCodeReviewFeedback} from '@github-ui/copilot-code-review-feedback/CopilotCodeReviewFeedback'
import {noop} from '@github-ui/noop'
import type {ReactionContent} from '@github-ui/reaction-viewer/ReactionGroupsUtils'
import {ReactionViewerBase} from '@github-ui/reaction-viewer/ReactionViewerBase'
import {ReactionViewerLoading} from '@github-ui/reaction-viewer/ReactionViewerLoading'
import {ReactionViewerRelay, ReactionViewerRelayQueryComponent} from '@github-ui/reaction-viewer/ReactionViewerRelay'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {SafeHTMLBox} from '@github-ui/safe-html'
import {ssrSafeLocation, ssrSafeWindow} from '@github-ui/ssr-utils'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {StopIcon} from '@primer/octicons-react'
import {Box, Flash, useConfirm} from '@primer/react'
import {Suspense, useCallback, useEffect, useRef, useState} from 'react'

import {useInlineCommentDialogModeContext} from '../contexts/InlineCommentDialogModeContext'
import {anchorComment} from '../helpers'
import {usePersistedDiffCommentData} from '../hooks/use-persisted-comment-data'
import type {
  ApplySuggestedChangesValidationData,
  Comment,
  CommentAuthor,
  CommentingImplementation,
  Subject,
  SuggestedChangesConfiguration,
  ViewerData,
} from '../types'
import {validateSuggestedChange} from '../util/validate-suggested-change'
import {ConversationCommentBox} from './ConversationCommentBox'
import {SuggestedChangeView} from './SuggestedChangeView'

type CommentState = 'editing' | 'hidden' | 'visible'

export interface ReviewThreadCommentProps {
  anchorPrefix?: string
  comment: Comment
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
  isFirstComment?: boolean
  isInlineComment: boolean
  isLastChild?: boolean
  isOutdated?: boolean
  isThreadResolved: boolean
  onRefreshThread?: (threadId: string) => void
  onQuoteReply?: (quotedText?: string) => void
  enterDialogMode?: (shouldFocusStartCommentButton?: boolean) => void
  repositoryId: string
  subject?: Subject
  subjectId: string
  suggestedChangesConfig?: SuggestedChangesConfiguration
  applySuggestedChangesValidationData?: ApplySuggestedChangesValidationData
  threadCommentCount?: number
  threadId: string
  threadPositionNumber?: number
  threadsConnectionId?: string
  viewerData?: ViewerData
  ghostUser?: CommentAuthor
  skipReactions?: boolean
  originalDiffPathUri?: string | null
}

export function ReviewThreadComment({
  isAnchorable = false,
  index = 0,
  isInlineComment,
  isLastChild,
  isOutdated,
  isThreadResolved,
  anchorPrefix = 'r',
  comment,
  commentingImplementation,
  filePath,
  hideActions,
  isFirstComment = false,
  enterDialogMode = noop,
  onRefreshThread,
  onQuoteReply = noop,
  subjectId,
  subject,
  threadCommentCount,
  threadId,
  threadPositionNumber,
  threadsConnectionId,
  suggestedChangesConfig,
  applySuggestedChangesValidationData,
  viewerData,
  ghostUser = VALUES.ghostUser,
  skipReactions = false,
  originalDiffPathUri,
}: ReviewThreadCommentProps): JSX.Element {
  const {addToast} = useToastContext()
  const [isEditing, setIsEditing] = useState(false)
  const [isMinimized, setIsMinimized] = useState(comment.isHidden)
  const [bodyText, setBodyText] = useState(comment.body)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | undefined>('')
  const {persistCommentToStorage, removePersistedCommentFromStorage} = usePersistedDiffCommentData({
    subjectId,
    filePath,
    fileLevelComment: comment.subjectType === 'FILE',
    threadId: comment.id,
    handlePersistedCommentExists: ({text}) => {
      if (!text) return
      setBodyText(text)
    },
  })
  const {
    blockUserFromOrg,
    unblockUserFromOrg,
    editComment,
    deleteComment,
    hideComment,
    unhideComment,
    reactToComment,
    lazyFetchReactionGroups,
  } = commentingImplementation
  const commentBoxRef = useRef<CommentBoxHandle>(null)
  const commentBodyRef = useRef<HTMLDivElement>(null)
  const [visibilityErrorMessage, setVisibilityErrorMessage] = useState('')

  const {isInDialogMode} = useInlineCommentDialogModeContext()

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

  const confirm = useConfirm()

  const {enableInlineCommentDialogMode, disableInlineCommentDialogMode} = useInlineCommentDialogModeContext()
  const onDelete = async () => {
    // when InlineCommentDialogMode is enabled, keyboard interactions are trapped in that div
    // we disable here so we can use keyboard interactions in the confirm dialog, which is outside the div
    disableInlineCommentDialogMode()
    let confirmed = false
    try {
      confirmed = await confirm({
        title: 'Delete comment?',
        content: 'Are you sure you want to delete this comment?',
        confirmButtonContent: 'Delete',
        confirmButtonType: 'danger',
      })
    } finally {
      enableInlineCommentDialogMode()
    }
    if (!confirmed) return
    // proceed with delete
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
      commentDatabaseId: comment.databaseId,
      reason,
      onCompleted: () => {
        setIsMinimized(true)
        onRefreshThread?.(threadId)
      },
      onError: () => {
        setIsSubmitting(false)
        setVisibilityErrorMessage('Failed to hide comment')
      },
    })
  }

  const onUnhide = () => {
    unhideComment({
      commentDatabaseId: comment.databaseId,
      onCompleted: () => {
        setIsMinimized(false)
        onRefreshThread?.(threadId)
      },
      onError: () => {
        setIsSubmitting(false)
        setVisibilityErrorMessage('Failed to unhide comment')
      },
    })
  }

  const onBlock = useCallback(
    (
      duration: string,
      shouldHideComment: boolean,
      hiddenReason: string | undefined,
      organizationLogin: string,
      notifyBlockedUser: boolean,
      userLogin: string,
    ) => {
      if (!blockUserFromOrg) return

      blockUserFromOrg({
        duration,
        shouldHideComment,
        hiddenReason,
        organizationLogin,
        notifyBlockedUser,
        userLogin,
        onCompleted: () => {
          if (shouldHideComment) {
            setIsMinimized(true)
          }
          onRefreshThread?.(threadId)
        },
        onError: () => {
          setVisibilityErrorMessage('Failed to block user')
        },
      })
    },
    [blockUserFromOrg, onRefreshThread, threadId],
  )

  const onUnblock = useCallback(
    (organizationLogin: string, userLogin: string) => {
      if (!unblockUserFromOrg) return

      unblockUserFromOrg({
        organizationLogin,
        userLogin,
        onCompleted: () => {
          onRefreshThread?.(threadId)
        },
        onError: () => {
          setVisibilityErrorMessage('Failed to unblock user')
        },
      })
    },
    [onRefreshThread, threadId, unblockUserFromOrg],
  )

  const onReact = (reaction: ReactionContent, viewerHasReacted: boolean) => {
    reactToComment?.({
      commentDatabaseId: comment.databaseId,
      threadId,
      reaction,
      viewerHasReacted,
      onCompleted: () => {
        onRefreshThread?.(threadId)
      },
      onError: () => {
        setIsSubmitting(false)
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: 'Failed to react to comment',
        })
      },
    })
  }

  const onEdit = () => {
    setIsEditing(true)
  }

  const onCancel = () => {
    setIsEditing(false)
    removePersistedCommentFromStorage()
    setBodyText(comment.body)
  }

  const onChange = (newBody: string) => {
    persistCommentToStorage({text: newBody})
    setBodyText(newBody)
    setErrorMessage(undefined)
  }

  const onSave = useCallback(() => {
    setIsSubmitting(true)

    const suggestedChangedEvaluation = validateSuggestedChange(
      bodyText,
      suggestedChangesConfig?.sourceContentFromDiffLines ?? '',
    )
    if (!suggestedChangedEvaluation.isValid) {
      setErrorMessage(suggestedChangedEvaluation.errorMessage)
      setIsSubmitting(false)

      return
    }

    editComment({
      text: bodyText,
      comment,
      onCompleted: () => {
        setIsEditing(false)
        setIsSubmitting(false)
        removePersistedCommentFromStorage()
        onRefreshThread?.(threadId)
      },
      onError: () => {
        setIsSubmitting(false)
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: 'Failed to update comment',
        })
      },
    })
  }, [
    addToast,
    bodyText,
    comment,
    editComment,
    onRefreshThread,
    removePersistedCommentFromStorage,
    suggestedChangesConfig,
    threadId,
  ])

  // The unique identifier for this comment in the DOM
  const commentId = comment.databaseId?.toString()

  // The anchor portion of the URL that will target this specific comment when navigating to it
  // This is used to scroll the comment into view and highlight it when directly linked
  const commentAnchor = commentId ? `${anchorPrefix}${commentId}` : undefined

  // The full URL including anchor that points directly to this comment within the current page
  const pageScopedCommentHref =
    commentAnchor && ssrSafeLocation
      ? new URL(`${ssrSafeLocation.pathname}#${commentAnchor}`, ssrSafeLocation.origin).toString()
      : ''
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
  const areSuggestedChangesEnabled = commentingImplementation.suggestedChangesEnabled

  const commentState: CommentState = isEditing ? 'editing' : isMinimized ? 'hidden' : 'visible'

  const commentActivityProps = {
    headingProps: {as: 'h3'} as ActivityHeaderHeadingProps,
    avatarUrl: comment.author?.avatarUrl ?? ghostUser.avatarUrl,
    comment: {
      ...comment,
      url: pageScopedCommentHref,
      referenceText: comment.reference.text ?? `#${comment.reference.number}`,
    },
    commentRef: containerRef,
    deleteComment: onDelete,
    editComment: onEdit,
    editHistoryComponent: undefined,
    hideComment: onHide,
    onBlock,
    onUnblock,
    onMinimize: setIsMinimized,
    onSuccessfulBlock: () => {
      //not ideal, but this is the easiest way to get all of the comments to reflect the newly updated state
      setTimeout(() => ssrSafeWindow?.location.reload(), 800)
    },
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
    originalDiffPathUri,
    isOutdated,
    commentAuthorSlug: comment.reviewVariantType === 'copilot' ? 'copilot-pull-request-reviewer' : undefined,
    commentAuthorType: comment.reviewVariantType === 'copilot' ? 'Bot' : undefined,
  }

  const getCommentAriaLabel = (): string => {
    if (isReply) {
      return threadPositionNumber !== undefined ? `Reply ${index} to Comment ${threadPositionNumber}` : `Reply ${index}`
    } else if (threadPositionNumber !== undefined) {
      return `Comment ${threadPositionNumber}`
    } else {
      return 'Comment'
    }
  }

  return (
    <Box
      ref={containerRef}
      id={isAnchorable ? commentAnchor : undefined}
      tabIndex={isInlineComment ? (isInDialogMode ? 0 : -1) : 0}
      data-first-thread-comment={isFirstComment}
      data-marker-navigation-comment-thread-id={threadId}
      data-marker-navigation-comment-id={comment.id}
      // When aria-label and role is set while still in gridcell mode, the browser doesn't the respect the
      // aria-hidden"true" and we end up with the aria-labels leaking into the accessible name of the gridcell,
      // which is not what we want. So we should only set these attributes while in dialog mode.
      {...(isInDialogMode
        ? {
            role: 'document',
            'aria-roledescription': 'comment',
            'aria-label': getCommentAriaLabel(),
          }
        : {})}
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
        // 120px is the approximately size of the PR/commits sticky header + diff header
        scrollMarginTop: isAnchorable ? '120px' : 0,
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
          {...commentActivityProps}
          commentBody={comment.body}
          threadCommentCount={threadCommentCount}
          isInDialogMode={isInDialogMode}
          actions={hideActions ? undefined : <CommentActions {...commentActivityProps} />}
          isOutdated={isOutdated}
        />
      </Box>
      {visibilityErrorMessage && (
        <Flash variant="danger" className="m-3">
          <StopIcon className="mr-2" />
          {visibilityErrorMessage}
        </Flash>
      )}
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

        {commentState === 'editing' && (
          <Box sx={{pr: 2, pl: isReply ? 0 : 2, pb: 2, pt: 1, flexGrow: 1}}>
            <ConversationCommentBox
              ref={commentBoxRef}
              label="Update comment"
              value={bodyText}
              onChange={onChange}
              onPrimaryAction={onSave}
              userSettings={commentingImplementation.commentBoxConfig}
              subject={commentingImplementation.commentBoxSubject}
              suggestedChangesConfig={suggestedChangesConfig}
              markdownErrorMessage={errorMessage}
            >
              <CommentBoxButton variant="default" onClick={onCancel}>
                Cancel
              </CommentBoxButton>
              <CommentBoxButton disabled={isSubmitting || !bodyText.length} variant="primary" onClick={onSave}>
                Update
              </CommentBoxButton>
            </ConversationCommentBox>
          </Box>
        )}

        {commentState === 'visible' && (
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
                {comment.reviewVariantType === 'copilot' && (
                  <p className="text-small color-fg-muted mt-2 mb-1">
                    <a
                      target="_blank"
                      rel="noopener noreferrer"
                      className="Link--inTextBlock"
                      href="https://docs.github.com/en/copilot/responsible-use-of-github-copilot-features/responsible-use-of-github-copilot-code-review"
                    >
                      Copilot
                    </a>{' '}
                    uses AI. Check for mistakes.
                  </p>
                )}
                <div className="d-flex flex-direction-column gap-2">
                  {comment.reviewVariantType === 'copilot' && (
                    <div className="mt-2">
                      <CopilotCodeReviewFeedback
                        commentUrl={comment.url}
                        commentId={comment.databaseId?.toString() ?? ''}
                      />
                    </div>
                  )}
                  {comment.reactionGroups && reactToComment ? (
                    <div className="d-flex flex-direction-column mt-2">
                      <ReactionViewerBase
                        reactionGroups={comment.reactionGroups}
                        onReact={onReact}
                        canReact={comment.viewerCanReact}
                      />
                    </div>
                  ) : (
                    !skipReactions && (
                      <Box sx={{display: 'flex', flexDirection: 'column', mt: 3}}>
                        {lazyFetchReactionGroups ? (
                          <Suspense fallback={<ReactionViewerLoading />}>
                            <ReactionViewerRelayQueryComponent
                              id={comment.id}
                              // subjectLocked is used as a gatekeeper for blocking interaction submissions for users who can not react on the comment.
                              subjectLocked={!comment.viewerCanReact}
                            />
                          </Suspense>
                        ) : (
                          <ReactionViewerRelay
                            reactionGroups={comment}
                            subjectId={comment.id}
                            canReact={comment.viewerCanReact}
                          />
                        )}
                      </Box>
                    )
                  )}
                </div>
                {areSuggestedChangesEnabled && applySuggestedChangesValidationData && (
                  <SuggestedChangeView
                    comment={comment}
                    commentBodyRef={commentBodyRef}
                    commentingImplementation={commentingImplementation}
                    filePath={filePath}
                    isOutdated={isOutdated}
                    isThreadResolved={isThreadResolved}
                    databaseId={comment.databaseId}
                    suggestedChangesConfig={suggestedChangesConfig}
                    applySuggestedChangesValidationData={applySuggestedChangesValidationData}
                    subject={subject}
                    viewerData={viewerData}
                  />
                )}
              </>
            )}
          </Box>
        )}
      </Box>
    </Box>
  )
}
