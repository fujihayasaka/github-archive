import {
  type Comment,
  type CommentingImplementation,
  ReviewThreadComment,
  StaticUnifiedDiffPreview,
} from '@github-ui/conversations'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {ChevronRightIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {memo, useCallback} from 'react'

import {usePullRequestCommenting} from '../../hooks/use-pull-request-commenting'
import {ThreadHeader} from './ThreadHeader'
import type {ThreadPreview as ThreadPreviewType} from '../../page-data/payloads/thread-previews'
import {PreviewAuthors} from './PreviewAuthors'
import {usePageDataContext} from '@github-ui/pull-request-page-data-tooling/page-data-context'

function panelThreadCollapsedStateStorageKey(id: string) {
  return `panel-thread-collapsed-state-${id}`
}

type ThreadPreviewProps = {
  commentBoxConfig: CommentingImplementation['commentBoxConfig']
  onNavigateToDiffComment: () => void
  pullRequestId: string
  repositoryId: string
  tabSize?: number
  thread: ThreadPreviewType
}

/**
 * Renders a preview of a thread in a pull request.
 * It displays the thread's header, the difflines that the
 * thread is associated with, and the first comment of the thread.
 */
export const ThreadPreview = memo(function ThreadPreview({
  commentBoxConfig,
  onNavigateToDiffComment,
  pullRequestId,
  repositoryId,
  tabSize,
  thread,
}: ThreadPreviewProps) {
  const firstComment = thread.firstComment
  const threadId = thread.threadId
  const isOutdated = thread.isOutdated
  const commentId = firstComment?.id
  const filePath = thread.path

  const navigateToComment = useCallback(() => {
    if (isOutdated && thread.originalDiffPathUri) {
      // eslint-disable-next-line no-restricted-syntax
      const url = new URL(thread.originalDiffPathUri)
      url.searchParams.set('new_files_changed', 'true')
      window.location.href = url.toString()
    } else {
      window.location.hash = `#r${firstComment?.databaseId}`
    }
    onNavigateToDiffComment()
  }, [isOutdated, thread.originalDiffPathUri, onNavigateToDiffComment, firstComment?.databaseId])

  const {basePageDataUrl} = usePageDataContext()

  // We don't need the subject or the oid because we can't make comments or commit suggestsions from previews
  const commentingImplementation = usePullRequestCommenting(basePageDataUrl, commentBoxConfig, '', undefined)
  const [isCollapsed, setIsCollapsed] = useLocalStorage(panelThreadCollapsedStateStorageKey(threadId), false)

  const replyCount = thread.threadPreviewComments.length
  const repliesText = replyCount === 0 ? 'No replies' : `${replyCount} ${replyCount === 1 ? 'reply' : 'replies'}`
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
        commentingImplementation={commentingImplementation}
        firstCommentId={firstComment?.databaseId}
        isCollapsed={isCollapsed}
        thread={thread}
        onNavigateToDiffComment={navigateToComment}
        onToggleCollapsed={() => setIsCollapsed(!isCollapsed)}
      />
      {!isCollapsed && (
        <>
          <div className="border-bottom borderColor-muted overflow-x-auto">
            <StaticUnifiedDiffPreview
              diffTableSx={{borderStyle: 'none'}}
              hideHeaderDetails
              subject={threadDiffPreview.subject}
              sx={{m: 0, borderStyle: 'none'}}
              tabSize={tabSize || 4}
            />
          </div>
          <div>
            <ReviewThreadComment
              key={commentId}
              hideActions
              isInlineComment={false}
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
              originalDiffPathUri={thread.originalDiffPathUri}
            />
          </div>
          <div className="mb-2 px-2">
            <Button
              aria-label="View comment in diff"
              size="small"
              trailingVisual={ChevronRightIcon}
              variant="invisible"
              onClick={navigateToComment}
            >
              <div className="d-flex flex-row flex-justify-start flex-items-center gap-2">
                <span>{repliesText}</span>
                <PreviewAuthors comments={thread.threadPreviewComments} />
              </div>
            </Button>
          </div>
        </>
      )}
    </div>
  )
})
