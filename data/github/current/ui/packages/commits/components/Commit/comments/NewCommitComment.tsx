import {ReadonlyCommentBox} from '@github-ui/comment-box/ReadonlyCommentBox'
import {blockedCommentingReason} from '@github-ui/commenting/blockedCommentingReason'
import {CompactCommentButton} from '@github-ui/commenting/CompactCommentButton'
import {IDS} from '@github-ui/commenting/DomElements'
import type {MarkdownComposerRef} from '@github-ui/commenting/useMarkdownBody'
import {VALUES} from '@github-ui/commenting/Values'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {LockIcon} from '@primer/octicons-react'
import {type LegacyRef, useRef, useState} from 'react'

import {useCommenting} from '../../../hooks/use-commenting'
import type {CommitComment} from '../../../types/commit-types'
import {CommitCommentEditor} from './CommitCommentEditor'

export function NewCommitComment({
  commitOid,
  onAddComment,
  onExpandCommentEditor,
  newCommentContent,
  canComment,
  locked,
  repoArchived,
  avatarURL,
}: {
  commitOid: string
  onAddComment: (comment: CommitComment) => void
  onExpandCommentEditor?: () => void
  newCommentContent?: string
  canComment: boolean
  locked: boolean
  repoArchived: boolean
  avatarURL?: string
}) {
  const {addComment} = useCommenting()

  const commentEditor = useRef<MarkdownComposerRef>(null)

  const onSave = async (markdown: string, resetMarkdownBody: () => void) => {
    const result = await addComment(markdown)

    if (result.comment) {
      onAddComment(result.comment)
      resetMarkdownBody()
    } else {
      // TODO - handle error
    }
  }

  const reason = blockedCommentingReason(repoArchived, locked)

  return (
    <div className="d-flex flex-column gap-2 pt-3">
      {canComment ? (
        <CompactEditor
          commitOid={commitOid}
          commentEditor={commentEditor}
          onExpandEditor={onExpandCommentEditor}
          onSave={onSave}
          newCommentContent={newCommentContent}
          avatarURL={avatarURL || VALUES.ghostUser.avatarUrl}
        />
      ) : (
        <ReadonlyCommentBox icon={LockIcon} reason={reason} />
      )}
    </div>
  )
}

function CompactEditor(props: {
  commitOid: string
  commentEditor: LegacyRef<MarkdownComposerRef> | undefined
  onExpandEditor?: () => void
  onSave: (markdown: string, restMarkdownBody: () => void) => Promise<void>
  newCommentContent?: string
  avatarURL: string
}) {
  const [isReplying, setIsReplying] = useState<boolean>(false)
  const buttonText = 'Comment'
  return isReplying ? (
    <div id={IDS.issueCommentComposer}>
      <CommitCommentEditor
        commitOid={props.commitOid}
        ref={props.commentEditor}
        onSave={props.onSave}
        referenceId={`new-discussion-comment-${props.commitOid}`}
        commentContent={props.newCommentContent}
        buttonText={buttonText}
        onCancel={() => {
          setIsReplying(false)
        }}
      />
    </div>
  ) : (
    <div className="d-flex flex-items-center border rounded-2 p-2 gap-2 color-bg-subtle">
      <GitHubAvatar src={props.avatarURL} size={20} />
      <CompactCommentButton
        onClick={() => {
          setIsReplying(true)
          props.onExpandEditor?.()
        }}
      >
        {buttonText}
      </CompactCommentButton>
    </div>
  )
}
