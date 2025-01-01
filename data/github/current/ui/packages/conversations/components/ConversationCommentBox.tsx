import {CommentBox, type CommentBoxHandle, type CommentBoxProps} from '@github-ui/comment-box/CommentBox'
import type {SxProp} from '@primer/react'
import type {ForwardedRef} from 'react'
import type React from 'react'
import {forwardRef} from 'react'

import type {Subject} from '../types'

export type ConversationCommentBoxProps = Omit<CommentBoxProps, 'children' | 'body'> & {
  children?: React.ReactNode
  label: string
  value: string
  /**
   * Markdown subject for the comment box. This is used to determine the context of the comment.
   * For example, when a RepoSubject is provided, features such as image upload, mentions, and emojis are enabled.
   * Pass in `undefined` if not providing a subject.
   * We require an explicit subject value or `undefined` to avoid implicit feature opt-outs.
   */
  subject: Subject | undefined
} & SxProp

export const ConversationCommentBox = forwardRef(
  ({children, subject, ...rest}: ConversationCommentBoxProps, ref: ForwardedRef<CommentBoxHandle>) => {
    return (
      <CommentBox
        {...rest}
        ref={ref}
        placeholder="Leave a comment"
        actions={children}
        subject={subject}
        showLabel={false}
      />
    )
  },
)

ConversationCommentBox.displayName = 'ConversationCommentBox'
