import {type Comment, ReviewThreadComment, StaticUnifiedDiffPreview} from '@github-ui/conversations'
import {GitHubAvatar} from '@github-ui/github-avatar'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {ChevronRightIcon} from '@primer/octicons-react'
import {AvatarStack, Button} from '@primer/react'
import {memo, useCallback} from 'react'

import {usePullRequestCommenting} from '../hooks/use-pull-request-toolbar-commenting'
import {ThreadHeader} from './ThreadHeader'
import type {ThreadPreview as ThreadPreviewType} from '../page-data/payloads/thread-previews'

function panelThreadCollapsedStateStorageKey(id: string) {
  return `panel-thread-collapsed-state-${id}`
}

function extractCommentAuthors(comments: CommentPreviews[]): Author[] {
  const uniqueAuthors = new Set<string>()
  const extractedAuthors = comments.reduce((authors, commentData) => {
    if (commentData?.author && !uniqueAuthors.has(commentData.author.login)) {
      authors.push({
        avatarUrl: commentData.author.avatarUrl,
        login: commentData.author.login,
      })
      uniqueAuthors.add(commentData.author.login)
    }

    return authors
  }, [] as Author[])

  return extractedAuthors ?? []
}

interface Author {
  avatarUrl: string
  login: string
}

function Authors({authors}: {authors: Author[]}) {
  if (authors.length < 1) return null

  return (
    <AvatarStack>
      {authors.map(({login, avatarUrl}) => (
        <GitHubAvatar key={login} alt={login} size={18} src={avatarUrl} />
      ))}
    </AvatarStack>
  )
}

type ThreadPreviewProps = {
  onNavigateToDiffThread: (threadId: string) => void
  pullRequestId: string
  repositoryId: string
  tabSize?: number
  thread: ThreadPreviewType
}

export interface CommentPreviews {
  author?: Author | null
}

/**
 * Renders a preview of a thread in a pull request.
 * It displays the thread's header, the difflines that the
 * thread is associated with, and the first comment of the thread.
 */
export const ThreadPreview = memo(function ThreadPreview({
  onNavigateToDiffThread,
  pullRequestId,
  repositoryId,
  tabSize,
  thread,
}: ThreadPreviewProps) {
  const firstComment = thread.firstComment

  const threadId = thread.id
  const isOutdated = thread.isOutdated
  const commentId = firstComment?.id
  const filePath = thread.path

  const navigateToThread = useCallback(() => {
    onNavigateToDiffThread(threadId)
  }, [onNavigateToDiffThread, threadId])

  const commentingImplementation = usePullRequestCommenting({lazyFetchReactionGroups: true})
  const [isCollapsed, setIsCollapsed] = useLocalStorage(panelThreadCollapsedStateStorageKey(threadId), false)

  const authors = extractCommentAuthors(thread.threadPreviewComments)
  const authorsCount = authors.length
  const repliesText = authorsCount === 0 ? 'No replies' : `${authorsCount} ${authorsCount === 1 ? 'reply' : 'replies'}`
  // The StaticUnifiedDiffPreview only looks at the subject, should probably by updated to only require that but for now
  // clean the comments so we don't have to match the typing by requesting a ton more data.
  const threadDiffPreview: ThreadPreviewType & {commentsData: {comments: Comment[]}} = {
    ...thread,
    commentsData: {comments: []},
  }

  if (!commentingImplementation || !firstComment || !threadDiffPreview) return null

  return (
    <div className="border rounded-2 d-flex flex-column">
      <ThreadHeader
        isCollapsed={isCollapsed}
        thread={thread}
        onNavigateToDiffThread={navigateToThread}
        onToggleCollapsed={() => setIsCollapsed(!isCollapsed)}
      />
      {!isCollapsed && (
        <>
          <div className="border borderColor-muted overflow-x-auto">
            <StaticUnifiedDiffPreview
              diffTableSx={{borderStyle: 'none'}}
              hideHeaderDetails
              sx={{m: 0, borderStyle: 'none'}}
              tabSize={tabSize || 4}
              thread={threadDiffPreview}
            />
          </div>
          <div>
            <ReviewThreadComment
              key={commentId}
              hideActions
              comment={firstComment}
              commentingImplementation={commentingImplementation}
              filePath={filePath}
              index={0}
              isAnchorable={false}
              isOutdated={isOutdated}
              isThreadResolved={thread.isResolved}
              repositoryId={repositoryId}
              subjectId={pullRequestId}
              threadId={threadId}
            />
          </div>
          <div className="mb-2 px-2">
            <Button
              aria-label="View thread in diff"
              size="small"
              trailingVisual={ChevronRightIcon}
              variant="invisible"
              onClick={navigateToThread}
            >
              <div className="d-flex flex-row flex-justify-start flex-items-center gap-2">
                <span>{repliesText}</span>
                <Authors authors={authors} />
              </div>
            </Button>
          </div>
        </>
      )}
    </div>
  )
})
