import type {CommentBoxConfig, CommentBoxHandle} from '@github-ui/comment-box/CommentBox'
import {CommentBoxButton} from '@github-ui/comment-box/CommentBoxButton'
import type {RepoSubject} from '@github-ui/comment-box/subject'
import {ssrSafeDocument, ssrSafeWindow} from '@github-ui/ssr-utils'
import {type BetterSystemStyleObject, Box} from '@primer/react'
import {useCallback, useEffect, useRef, useState} from 'react'

import {usePersistedDiffCommentData} from '../hooks/use-persisted-comment-data'
import type {DiffSide, SuggestedChangesConfiguration} from '../types'
import {validateSuggestedChange} from '../util/validate-suggested-change'
import {ConversationCommentBox} from './ConversationCommentBox'

export interface AddCommentEditorProps {
  batchPending?: boolean
  batchingEnabled?: boolean
  commentBoxConfig: CommentBoxConfig
  commentBoxSubject: RepoSubject | undefined
  condensed: boolean
  fileLevelComment?: boolean
  filePath: string
  focusOnMount?: boolean
  isReplying?: boolean
  lineNumber?: number
  onAddComment?: (args: {
    commentText: string
    onCompleted?: () => void
    onError: (error: Error) => void
    submitBatch?: boolean
  }) => void
  onCancelComment?: () => void
  onPersistedCommentExists?: () => void
  repositoryId: string
  quotedText?: string
  side?: DiffSide
  startLineNumber?: number
  subjectId: string
  threadId?: string
  suggestedChangesConfig?: SuggestedChangesConfiguration
}

export function AddCommentEditor({
  batchPending,
  batchingEnabled,
  commentBoxConfig,
  commentBoxSubject,
  condensed,
  fileLevelComment,
  filePath,
  focusOnMount,
  isReplying,
  lineNumber,
  onAddComment,
  onCancelComment,
  onPersistedCommentExists,
  quotedText = '',
  side,
  startLineNumber,
  subjectId,
  threadId,
  suggestedChangesConfig,
}: AddCommentEditorProps) {
  const [commentText, setCommentText] = useState(quotedText)
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false)
  const [errorMessage, setErrorMessage] = useState<string | undefined>()
  const editorRef = useRef<CommentBoxHandle>(null)
  const commentButtonRef = useRef<HTMLButtonElement>(null)

  const {persistCommentToStorage, removePersistedCommentFromStorage} = usePersistedDiffCommentData({
    diffSide: side,
    filePath,
    line: lineNumber,
    subjectId,
    threadId,
    handlePersistedCommentExists: ({text}) => {
      if (!text) return
      setCommentText(text)
      onPersistedCommentExists?.()
    },
    fileLevelComment: !!fileLevelComment,
  })

  useEffect(() => {
    if (focusOnMount) {
      const timeout = setTimeout(() => {
        // If the comment button is not in view, scroll it into view, so the user can see the comment box
        if (commentButtonRef.current && (ssrSafeDocument || ssrSafeWindow)) {
          const commentButton = commentButtonRef.current
          const commentButtonRect = commentButton.getBoundingClientRect()
          const documentClientHeight = ssrSafeDocument?.documentElement.clientHeight || 0
          const commentButtonIsVisible =
            commentButtonRect.top >= 0 &&
            commentButtonRect.bottom <= (ssrSafeWindow?.innerHeight || documentClientHeight)

          if (!commentButtonIsVisible) {
            // this element will always be rendered below the fold if not visible, so we need to scroll it into view
            // we want this to sit comfortably above the fold, so we scroll it to 2/3 of the way down the viewport
            const targetTop = commentButtonRect.top
            const documentTop = ssrSafeDocument?.documentElement.getBoundingClientRect().top || 0
            const twoThirdsOfDocumentHeight = documentClientHeight * (2 / 3)
            const twoThirdsOfClientHeight = commentButton.clientHeight * (2 / 3)
            const targetScroll = targetTop - documentTop - twoThirdsOfDocumentHeight + twoThirdsOfClientHeight

            ssrSafeWindow?.scrollTo({top: targetScroll, behavior: 'smooth'})
          }
        }

        editorRef.current?.focus()
      }, 100)

      return () => {
        window.clearTimeout(timeout)
      }
    }
  }, [focusOnMount])

  const handleAddComment = ({submitBatch}: {submitBatch: boolean}) => {
    let msg = 'Failed to save comment'

    if (isSubmitting) return

    if (!commentText.trim()) {
      setErrorMessage(`${msg}: Body can't be blank`)
      return
    }

    setIsSubmitting(true)
    setErrorMessage(undefined)

    const suggestedChangedEvaluation = validateSuggestedChange(
      commentText,
      suggestedChangesConfig?.sourceContentFromDiffLines ?? '',
    )
    if (!suggestedChangedEvaluation.isValid) {
      setErrorMessage(suggestedChangedEvaluation.errorMessage)
      setIsSubmitting(false)

      return
    }

    onAddComment?.({
      commentText,
      onCompleted() {
        setIsSubmitting(false)
        closeCommentBox()
      },
      onError(error) {
        setIsSubmitting(false)

        if (error.message) {
          msg = `${msg}: ${error.message}`
        }
        setErrorMessage(msg)
      },
      submitBatch,
    })
  }

  const handleAddReviewComment = () => handleAddComment({submitBatch: false})
  const handleAddSingleComment = () => handleAddComment({submitBatch: true})

  const closeCommentBox = useCallback(() => {
    removePersistedCommentFromStorage()
    setCommentText('')
    onCancelComment?.()
  }, [onCancelComment, removePersistedCommentFromStorage])

  const handleCommentTextChange = (text: string) => {
    setErrorMessage(undefined)
    persistCommentToStorage({text})
    setCommentText(text)
  }

  // Hide the MarkdownEditor's "Markdown supported" footer when the form is condensed
  const markdownOptionsStyles: BetterSystemStyleObject = {
    '> div:first-child': {
      display: condensed || isReplying ? 'none' : 'flex',
    },
  }
  // Stack the markdown actions when the form is condensed
  const stackMarkdownActions: BetterSystemStyleObject = {
    '> div:last-child': {display: 'flex', flexDirection: 'column', width: '100%'},
  }

  const footerStyles: BetterSystemStyleObject = {
    footer: {
      justifyContent: isReplying ? 'end' : 'space-between',
      ...markdownOptionsStyles,
      ...(condensed && stackMarkdownActions),
    },
  }

  return (
    <Box
      sx={{
        display: 'flex',
        // this fixes the flash errors being displayed to the left of the text box in the same row
        flexDirection: 'column',
        // This is here to prevent this component from being rendered with overflow off screen due to the MarkdownEditor
        // having styling issues with its use of a `<fieldset>` element and the parent `<tr>` and `<td>` elements.
        fieldset: {
          minWidth: 0,
          width: ['100%'],
        },
      }}
      onKeyDown={event => {
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        if (event.key === 'Escape' && !commentText.trim()) {
          event.preventDefault()
          closeCommentBox()
        } else {
          event.stopPropagation()
        }
      }}
    >
      <ConversationCommentBox
        ref={editorRef}
        label="Add diff comment"
        sx={footerStyles}
        value={commentText}
        onChange={handleCommentTextChange}
        onPrimaryAction={batchingEnabled ? handleAddReviewComment : handleAddSingleComment}
        userSettings={commentBoxConfig}
        suggestedChangesConfig={suggestedChangesConfig}
        markdownErrorMessage={errorMessage}
        subject={commentBoxSubject}
        lineNumber={lineNumber}
        filePath={filePath}
        startLineNumber={startLineNumber}
      >
        {onCancelComment && (
          <CommentBoxButton disabled={isSubmitting} sx={{py: 1, px: 2}} variant="default" onClick={closeCommentBox}>
            Cancel
          </CommentBoxButton>
        )}
        {!batchPending && (
          <CommentBoxButton
            disabled={isSubmitting || !commentText.length}
            sx={{py: 1, px: 2}}
            variant={batchingEnabled ? 'default' : 'primary'}
            onClick={handleAddSingleComment}
            ref={commentButtonRef}
          >
            {isReplying ? 'Reply' : 'Comment'}
          </CommentBoxButton>
        )}
        {batchingEnabled && (
          <CommentBoxButton
            disabled={isSubmitting || !commentText.length}
            sx={{py: 1, px: 2}}
            variant="primary"
            onClick={handleAddReviewComment}
          >
            {batchPending ? 'Add review comment' : 'Start a review'}
          </CommentBoxButton>
        )}
      </ConversationCommentBox>
    </Box>
  )
}
