import {CommentBox, type CommentBoxHandle} from '@github-ui/comment-box/CommentBox'
import {type MarkdownComposerRef, useMarkdownBody} from '@github-ui/commenting/useMarkdownBody'
import {useConversationMarkdownSubjectContext} from '@github-ui/conversations'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {forwardRef, useCallback, useEffect, useRef, useState} from 'react'

import {useCommenting} from '../../../hooks/use-commenting'

const CommitCommentEditor = forwardRef<
  MarkdownComposerRef,
  {
    commentContent?: string
    initialMarkdown?: string
    commitOid: string
    onCancel?: () => void
    onSave: (markdown: string, restMarkdownBody: () => void) => Promise<void>
    referenceId: string
    buttonText: string
  }
>(({initialMarkdown, onCancel, onSave, referenceId, buttonText, commentContent}, ref) => {
  const [saving, setSaving] = useState<boolean>(false)
  const commentBoxRef = useRef<CommentBoxHandle | null>(null)
  const definedCommentContent = useRef<string | undefined>(undefined)

  const onChange = useCallback(() => {}, [])

  const {markdownBody, resetMarkdownBody, markdownValidationResult, handleMarkdownBodyChanged} = useMarkdownBody({
    commentBoxRef,
    markdownComposerRef: ref,
    onChange,
    onCancel: () => {},
    referenceId,
  })

  useEffect(() => {
    // Don't override the markdown saved in the session
    if (initialMarkdown && !markdownBody) {
      handleMarkdownBodyChanged(initialMarkdown)
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialMarkdown])

  useEffect(() => {
    if (commentContent && definedCommentContent.current !== commentContent) {
      handleMarkdownBodyChanged(commentContent)
      definedCommentContent.current = commentContent
      const timeout = window.setTimeout(() => {
        if (commentBoxRef.current) {
          commentBoxRef.current?.scrollIntoView()
          commentBoxRef.current?.focus()
        }
      }, 0)

      return () => {
        window.clearTimeout(timeout)
      }
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [commentContent])

  useLayoutEffect(() => {
    if (commentBoxRef && commentBoxRef.current) {
      const timeout = window.setTimeout(() => {
        commentBoxRef.current?.focus()
      }, 0)

      return () => {
        window.clearTimeout(timeout)
      }
    }
  }, [commentBoxRef])

  const onSaveInt = async () => {
    setSaving(true)
    await onSave(markdownBody, resetMarkdownBody)
    setSaving(false)
  }

  const subject = useConversationMarkdownSubjectContext() || undefined

  return (
    <CommentBox
      ref={commentBoxRef}
      validationResult={markdownValidationResult}
      disabled={saving}
      onChange={newMarkdown => {
        handleMarkdownBodyChanged(newMarkdown)
      }}
      onCancel={() => {
        handleMarkdownBodyChanged(initialMarkdown ?? '')
        onCancel?.()
      }}
      onSave={onSaveInt}
      saveButtonText={buttonText}
      saveButtonTrailingIcon={false}
      value={markdownBody}
      teamHovercardsEnabled
      fileUploadsEnabled
      userSettings={useCommenting().commentBoxConfig}
      subject={subject}
    />
  )
})

CommitCommentEditor.displayName = 'CommitCommentEditor'
export {CommitCommentEditor}
