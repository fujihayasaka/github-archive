import {ActivityHeader} from '@github-ui/commenting/ActivityHeader'
import {CommentActions, type CommentData} from '@github-ui/commenting/CommentActions'
import type {CommentHeaderProps} from '@github-ui/commenting/CommentHeader'
import {useCurrentRepository} from '@github-ui/current-repository'
import {MarkdownEditHistoryViewer} from '@github-ui/markdown-edit-history-viewer/MarkdownEditHistoryViewer'
import {MarkdownLastEditedBy} from '@github-ui/markdown-edit-history-viewer/MarkdownLastEditedBy'
import {useMarkdownEditHistoryViewerQuery} from '@github-ui/markdown-edit-history-viewer/use-markdown-edit-history-viewer-query'
import {MarkdownViewer} from '@github-ui/markdown-viewer'
import {ReactionViewerLoading} from '@github-ui/reaction-viewer/ReactionViewerLoading'
import {ReactionViewerRelayQueryComponent} from '@github-ui/reaction-viewer/ReactionViewerRelay'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {Suspense, useRef, useState} from 'react'
import type {FragmentRefs} from 'relay-runtime'

import {useCommenting} from '../../../hooks/use-commenting'
import {mapCommitCommentToComment} from '../../../hooks/use-fetch-commit-thread'
import type {BaseCommit} from '../../../shared/types'
import type {CommitComment} from '../../../types/commit-types'
import {shortSha} from '../../../utils/short-sha'
import {UpdateCommitComment} from './UpdateCommitComment'

type CommentDataWithMarkdownEditHistoryViewer = CommentData & {
  ' $fragmentSpreads': FragmentRefs<
    'MarkdownEditHistoryViewer_comment' | 'MarkdownLastEditedBy' | 'ReactionViewerRelayGroups'
  >
}

export function ExistingCommitComments({
  comments,
  commit,
  locked,
  deleteComment,
  updateComment,
  setNewCommentContent,
  repoOwnerGlobalRelayId,
}: {
  comments: CommitComment[]
  commit: BaseCommit
  locked: boolean
  deleteComment: (commentId: CommitComment['id']) => void
  updateComment: (comment: CommitComment) => void
  setNewCommentContent: (content?: string) => void
  repoOwnerGlobalRelayId: string
}) {
  if (comments.length === 0) {
    return null
  }

  return (
    <div className="d-flex flex-column gap-3">
      {comments.map(comment => {
        return (
          <ExistingCommitComment
            key={comment.id}
            comment={comment}
            commit={commit}
            locked={locked}
            deleteComment={deleteComment}
            updateComment={updateComment}
            setNewCommentContent={setNewCommentContent}
            repoOwnerGlobalRelayId={repoOwnerGlobalRelayId}
          />
        )
      })}
    </div>
  )
}

function ExistingCommitComment({
  comment,
  commit,
  locked,
  deleteComment: onDeleteComment,
  updateComment,
  setNewCommentContent,
  repoOwnerGlobalRelayId,
}: {
  comment: CommitComment
  commit: BaseCommit
  locked: boolean
  deleteComment: (commentId: CommitComment['id']) => void
  updateComment: (comment: CommitComment) => void
  setNewCommentContent: (content?: string) => void
  repoOwnerGlobalRelayId: string
}) {
  const repo = useCurrentRepository()

  const [isEditing, setIsEditing] = useState(false)
  const [isMinimized, setIsMinimized] = useState(comment.isHidden)
  const commentRef = useRef<HTMLDivElement>(null)
  const {deleteComment, hideComment, unhideComment} = useCommenting()

  const onDelete = async () => {
    const result = await deleteComment(comment.id.toString())

    if (result === 'canceled') {
      return
    }

    if (result === 'error') {
      // TODO - handle error
      return
    }

    if (result === 'success') {
      onDeleteComment(comment.id)
    }
  }

  const onUpdate = (updatedComment: CommitComment) => {
    updateComment(updatedComment)
    setIsEditing(false)
  }

  const onHide = async (reason: string) => {
    const result = await hideComment(comment.id.toString(), reason)

    if (result === 'error') {
      // TODO - handle error
      return
    }

    if (result === 'success') {
      updateComment({...comment, isHidden: true, minimizedReason: reason})
      setIsMinimized(true)
    }
  }

  const onUnhide = async () => {
    const result = await unhideComment(comment.id.toString())

    if (result === 'error') {
      // TODO - handle error
      return
    }

    if (result === 'success') {
      updateComment({...comment, isHidden: false, minimizedReason: null})
      setIsMinimized(false)
    }
  }

  // how to handle multiple authors?
  const commentSubjectAuthorLogin = commit.authors.length > 0 ? commit.authors[0]?.login : ''

  const commentDataWithoutFragment: Omit<CommentData, ' $fragmentSpreads'> = {
    ...mapCommitCommentToComment(comment, commit, repo, repoOwnerGlobalRelayId),
    referenceText: shortSha(commit.oid),
  }

  return (
    <div className="border rounded-2" ref={commentRef} id={comment.urlFragment} tabIndex={-1}>
      <CommitCommentHeader
        comment={commentDataWithoutFragment as CommentDataWithMarkdownEditHistoryViewer}
        commentAuthorLogin={comment.author.login}
        commentSubjectAuthorLogin={commentSubjectAuthorLogin}
        commentSubjectType="commit"
        avatarUrl={comment.author.avatarUrl}
        isMinimized={isMinimized}
        editComment={() => {
          setIsEditing(true)
        }}
        onReplySelect={setNewCommentContent}
        onMinimize={setIsMinimized}
        navigate={() => {}}
        hideComment={onHide}
        unhideComment={onUnhide}
        deleteComment={onDelete}
        commentRef={commentRef}
        showEditHistory={comment.viewerCanReadUserContentEdits && !!comment.lastUserContentEdit}
        commitComment={comment}
      />
      {isMinimized ? null : isEditing ? (
        <div className="m-2">
          <UpdateCommitComment
            comment={comment}
            commitOid={commit.oid}
            onUpdate={onUpdate}
            onCancel={() => setIsEditing(false)}
          />
        </div>
      ) : (
        <div className="d-flex flex-column m-3 gap-3" style={{gap: '12px'}}>
          <div className="markdown-body" data-turbolinks="false">
            <MarkdownViewer
              disabled={false}
              verifiedHTML={comment.htmlBody}
              markdownValue={comment.body}
              onChange={() => {}}
              onLinkClick={() => {}}
              teamHovercardsEnabled
            />
          </div>
          <Suspense fallback={<ReactionViewerLoading />}>
            <ReactionViewerRelayQueryComponent id={comment.relayId} subjectLocked={locked} />
          </Suspense>
        </div>
      )}
    </div>
  )
}
interface CommitCommentHeaderProps extends CommentHeaderProps {
  showEditHistory: boolean
  commitComment: CommitComment
}

function CommitCommentHeader({hideActions, ...props}: CommitCommentHeaderProps) {
  let editHistoryComponent = undefined
  let editLastEditedByComponent = undefined
  const comment = props.commitComment

  if (props.showEditHistory) {
    editHistoryComponent = (
      <Suspense fallback={null}>
        <CommitCommentHeaderEditHistory id={comment.relayId} />
      </Suspense>
    )
    editLastEditedByComponent = <CommitCommentHeaderLastEditedBy id={props.comment.id} />
  }

  return (
    <ActivityHeader
      lastEditedByMessage={editLastEditedByComponent}
      editHistoryComponent={editHistoryComponent}
      forceInlineAvatar
      {...props}
      actions={
        hideActions ? undefined : (
          <CommentActions
            onSuccessfulBlock={() => {
              //not ideal, but this is the easiest way to get all of the comments to reflect the newly updated state
              setTimeout(() => ssrSafeWindow?.location.reload(), 800)
            }}
            {...props}
          />
        )
      }
    />
  )
}

export function CommitCommentHeaderEditHistory({id}: {id: string}) {
  const data = useMarkdownEditHistoryViewerQuery({id})
  return data ? <MarkdownEditHistoryViewer editHistory={data} /> : null
}

export function CommitCommentHeaderLastEditedBy({id}: {id: string}) {
  const data = useMarkdownEditHistoryViewerQuery({id})
  return data ? <MarkdownLastEditedBy editInformation={data} /> : null
}
