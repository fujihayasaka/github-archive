/* eslint eslint-comments/no-use: off */
import {CLASS_NAMES} from '@github-ui/commenting/DomElements'
import {useCurrentRepository} from '@github-ui/current-repository'
import {useCurrentUser} from '@github-ui/current-user'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {KeyIcon, LockIcon} from '@primer/octicons-react'
import {Button, CounterLabel, Flash} from '@primer/react'
import {clsx} from 'clsx'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {useDiscussionComments} from '../../../contexts/DiscussionCommentsContext'
import type {CurrentUserExtended} from '../../../shared/types'
import type {CommitExtended, InitialCommentInfo} from '../../../types/commit-types'
import {isWeirichCommit} from '../../../utils/weirich-commit'
import styles from './Comment.module.css'
import {CommentLoading} from './CommentLoading'
import {ExistingCommitComments} from './ExistingCommitComments'
import {LockConversationDialog} from './LockConversationDialog'
import {NewCommitComment} from './NewCommitComment'
import {NotificationsFooter} from './NotificationFooter'

// id to jump to when navigating to the comments section from commits list
export const COMMENTS_CONTAINER_ID = 'comments'

export function DiscussionComments(props: {
  commit: CommitExtended
  commentInfo: InitialCommentInfo
  repoOwnerGlobalRelayId: string
}) {
  return (
    <div
      className={clsx(
        'd-flex flex-column gap-2 pt-3',
        CLASS_NAMES.commentsContainer,
        styles['commit-discussion-comments'],
      )}
      id={COMMENTS_CONTAINER_ID}
    >
      <DiscussionCommentsInternal {...props} key={props.commit.oid} />
    </div>
  )
}

function DiscussionCommentsInternal({
  commit,
  commentInfo,
  repoOwnerGlobalRelayId,
}: {
  commit: CommitExtended
  commentInfo: InitialCommentInfo
  repoOwnerGlobalRelayId: string
}) {
  const repo = useCurrentRepository()
  const currentUser = useCurrentUser() as CurrentUserExtended

  const {
    retry,
    loadMore,
    canLoadMore,
    addComment,
    deleteComment,
    updateComment,
    count: commentCount,
    comments,
    subscribed,
    providerState,
  } = useDiscussionComments()

  // Used for quote replies
  const [newCommentContent, setNewCommentContent] = useState<string | undefined>(undefined)
  const [locked, setLocked] = useState(commentInfo.locked)

  const isWeirichCommitValue = useMemo(() => isWeirichCommit(commit.oid, repo.id), [commit.oid, repo.id])

  const notificationFooterRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (ssrSafeWindow?.location.hash) {
      const urlFragment = ssrSafeWindow.location.hash.slice(1)
      const comment = comments.find(c => c.urlFragment === urlFragment)

      if (comment) {
        const commentElement = document.getElementById(urlFragment)
        if (commentElement) {
          commentElement.scrollIntoView()
          commentElement.focus()
        }
      }
    }
  }, [comments])

  const onExpandCommentEditor = useCallback(() => {
    setTimeout(() => notificationFooterRef.current?.scrollIntoView({behavior: 'smooth', block: 'nearest'}), 0)
  }, [])

  return (
    <>
      <DiscussionCommentsHeader
        commitOid={commit.oid}
        commentCount={commentCount}
        canLock={commentInfo.canLock}
        locked={locked}
        setLocked={setLocked}
      />
      {providerState === 'loading' && <CommentLoading />}
      {providerState === 'error' && (
        <Flash className="d-flex flex-justify-between flex-items-center" variant="danger">
          <span>Failed to load comments.</span>
          <Button onClick={() => retry()}>Retry</Button>
        </Flash>
      )}
      {providerState === 'loaded' && canLoadMore && (
        <Button className="width-full" onClick={() => loadMore()}>
          Load more comments
        </Button>
      )}
      <ExistingCommitComments
        comments={comments}
        commit={commit}
        locked={locked}
        repoOwnerGlobalRelayId={repoOwnerGlobalRelayId}
        deleteComment={deleteComment}
        updateComment={updateComment}
        setNewCommentContent={setNewCommentContent}
      />
      {isWeirichCommitValue ? (
        <div className="text-center">
          {[...Array(38)].map((_, i) => (
            <img
              // eslint-disable-next-line @eslint-react/no-array-index-key
              key={`rose-${i}`}
              alt="rose"
              src="/images/icons/emoji/rose.png"
              className={styles['discussion-comments-rose']}
            />
          ))}
        </div>
      ) : null}
      {providerState === 'loaded' || comments.length !== 0 ? (
        <>
          <NewCommitComment
            commitOid={commit.oid}
            onAddComment={addComment}
            onExpandCommentEditor={onExpandCommentEditor}
            newCommentContent={newCommentContent}
            canComment={commentInfo.canComment}
            locked={locked}
            repoArchived={commentInfo.repoArchived}
            avatarURL={currentUser?.avatarURL}
          />
          {currentUser ? (
            <NotificationsFooter ref={notificationFooterRef} commitOid={commit.oid} subscribed={subscribed ?? false} />
          ) : null}
        </>
      ) : null}
    </>
  )
}

function DiscussionCommentsHeader({
  commitOid,
  commentCount,
  locked,
  setLocked,
  canLock,
}: {
  commitOid: string
  commentCount: number | undefined
  locked: boolean
  setLocked: (locked: boolean) => void
  canLock: boolean
}) {
  const [lockDialogOpen, setLockDialogOpen] = useState(false)
  return (
    <div className="d-flex flex-items-center flex-justify-between">
      <h2 className="sr-only">{commentCount} commit comments</h2>
      <div className="d-flex flex-items-center">
        <div className="h4 pr-2">Comments</div>
        {commentCount !== undefined && <CounterLabel>{commentCount}</CounterLabel>}
      </div>
      {canLock && (
        <>
          <Button
            leadingVisual={locked ? KeyIcon : LockIcon}
            variant="invisible"
            onClick={() => setLockDialogOpen(true)}
          >
            {locked ? 'Unlock' : 'Lock'} conversation
          </Button>
          {lockDialogOpen && (
            <LockConversationDialog
              commitOid={commitOid}
              locked={locked}
              onClose={newLockedState => {
                setLockDialogOpen(false)
                if (newLockedState !== undefined) {
                  setLocked(newLockedState)
                }
              }}
            />
          )}
        </>
      )}
    </div>
  )
}
