import {GitHubAvatar} from '@github-ui/github-avatar'
import {NewMarkdownViewer} from '@github-ui/markdown-viewer/NewMarkdownViewer'
import {userHovercardPath} from '@github-ui/paths'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {AvatarStack, Button, Link, RelativeTime} from '@primer/react'
import {clsx} from 'clsx'
import {memo, useState} from 'react'

import type {Author, ThreadComment} from '../../utilities/workspace-editor-types'
import sharedStyles from './GenerateFix.module.css'
import styles from './PullRequestThread.module.css'

function extractCommentAuthors(comments: ThreadComment[]): Author[] {
  const uniqueAuthors = new Set<string>()
  const extractedAuthors = comments.reduce((authors, commentData) => {
    if (commentData.author && !uniqueAuthors.has(commentData.author.displayLogin)) {
      authors.push({
        avatarUrl: commentData.author.avatarUrl,
        displayLogin: commentData.author.displayLogin,
      })
      uniqueAuthors.add(commentData.author.displayLogin)
    }

    return authors
  }, [] as Author[])

  return extractedAuthors ?? []
}

function Authors({authors}: {authors: Author[]}) {
  if (authors.length === 0) return null

  return (
    <AvatarStack>
      {authors.map(({displayLogin, avatarUrl}) => (
        <GitHubAvatar key={displayLogin} alt={displayLogin} size={18} src={avatarUrl} />
      ))}
    </AvatarStack>
  )
}

function DefaultAvatar({avatarUrl = '', login = ''}: {avatarUrl?: string; login?: string}) {
  return (
    <GitHubAvatar data-hovercard-url={userHovercardPath({owner: login})} src={avatarUrl} size={24} alt={`@${login}`} />
  )
}

type RenderableThreadComment = Pick<ThreadComment, 'author' | 'body' | 'id'> & {
  createdAt?: string
}

export function ThreadComment({
  actorLinkable = true,
  comment,
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  actorAvatar = <DefaultAvatar avatarUrl={comment.author?.avatarUrl} login={comment.author?.displayLogin} />,
}: {
  actorAvatar?: JSX.Element
  actorLinkable?: boolean
  comment: RenderableThreadComment
}) {
  const {author, body, createdAt} = comment
  const {displayLogin} = author ?? {displayLogin: ''}
  const createdData = createdAt ? new Date(createdAt) : new Date()
  const actorStyles = clsx('color-fg-default f5 overflow-hidden', sharedStyles.actorName)

  return (
    <div className="d-flex flex-column gap-2">
      <div className="d-flex flex-items-center flex-row gap-2">
        {actorAvatar}
        {actorLinkable ? (
          <Link
            className={actorStyles}
            data-hovercard-url={userHovercardPath({owner: displayLogin})}
            href={displayLogin}
          >
            {displayLogin}
          </Link>
        ) : (
          <span className={actorStyles}>{displayLogin}</span>
        )}
        <RelativeTime date={createdData} className="color-fg-muted">
          on {createdData.toLocaleDateString('en-US', {month: 'short', day: 'numeric', year: 'numeric'})}{' '}
        </RelativeTime>
      </div>
      <NewMarkdownViewer verifiedHTML={body as SafeHTMLString} />
    </div>
  )
}

export const Comments = memo(function Comments({comments}: {comments: ThreadComment[]}) {
  return (
    <div className="d-flex flex-column gap-4">
      {comments.map(comment => (
        <ThreadComment key={comment.id} comment={comment} />
      ))}
    </div>
  )
})

export const PullThread = memo(function PullThread({
  comments,
  isCondensed,
}: {
  comments: ThreadComment[]
  isCondensed: boolean
}) {
  // only used when isCondensed is true
  const [isExpanded, setIsExpanded] = useState(false)

  if (!isCondensed) {
    return <Comments comments={comments} />
  }

  const firstComment = comments[0]!
  const replies = comments.slice(1)
  const authors = extractCommentAuthors(replies)
  const repliesCount = replies.length
  const repliesText = repliesCount > 1 ? `${repliesCount} replies` : '1 reply'
  return (
    <>
      <ThreadComment comment={firstComment} />
      {replies.length > 0 && (
        <>
          <span className={clsx(isExpanded && 'mb-2')}>
            <Button
              aria-label="View thread in diff"
              className={clsx('color-fg-muted', styles.threadSummaryButton)}
              size="small"
              trailingVisual={isExpanded ? ChevronDownIcon : ChevronRightIcon}
              variant="invisible"
              onClick={() => setIsExpanded(!isExpanded)}
            >
              <div className="d-flex flex-row flex-items-center gap-2 flex-justify-start">
                <span className="color-fg-muted">{repliesText}</span>
                <Authors authors={authors} />
              </div>
            </Button>
          </span>
          {isExpanded && <Comments comments={replies} />}
        </>
      )}
    </>
  )
})
