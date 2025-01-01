import {CheckCircleFillIcon, CheckCircleIcon, StopIcon} from '@primer/octicons-react'
import {Flash, IconButton} from '@primer/react'
import {usePullRequestToolbarAnalytics} from '../../hooks/use-pull-request-toolbar-analytics'
import {ConversationHeader} from './ConversationHeader'
import type {CommentingImplementation} from '@github-ui/conversations'
import {useState} from 'react'

interface ThreadHeaderData {
  threadId: string
  isOutdated: boolean
  isResolved: boolean
  line?: number | null
  path: string
}

type ThreadHeaderProps = {
  commentingImplementation: CommentingImplementation
  firstCommentId?: number | null
  isCollapsed: boolean
  onNavigateToDiffComment: () => void
  onToggleCollapsed: () => void
  thread: ThreadHeaderData
}

export function ThreadHeader({
  commentingImplementation,
  firstCommentId,
  isCollapsed,
  onToggleCollapsed,
  onNavigateToDiffComment,
  thread,
}: ThreadHeaderProps) {
  const {sendPullRequestAnalyticsEvent} = usePullRequestToolbarAnalytics()
  const [errorMessage, setErrorMessage] = useState<string | undefined>(undefined)

  const {resolveThread, unresolveThread} = commentingImplementation

  const handleResolveThread = () => {
    if (!thread.isResolved) {
      resolveThread({
        threadId: thread.threadId,
        onCompleted: () => {
          if (!isCollapsed) onToggleCollapsed()
        },
        onError: () => {
          setErrorMessage('Failed to resolve thread')
        },
      })
    }

    sendPullRequestAnalyticsEvent('comments.resolve_thread', 'RESOLVE_CONVERSATION_BUTTON')
  }

  const handleUnresolveThread = () => {
    if (thread.isResolved) {
      unresolveThread({
        threadId: thread.threadId,
        onCompleted: () => {
          if (isCollapsed) onToggleCollapsed()
        },
        onError: () => {
          setErrorMessage('Failed to unresolve thread')
        },
      })
    }

    sendPullRequestAnalyticsEvent('comments.unresolve_thread', 'RESOLVE_CONVERSATION_BUTTON')
  }

  return (
    <>
      <ConversationHeader
        firstCommentId={firstCommentId}
        isCollapsed={isCollapsed}
        isOutdated={thread.isOutdated}
        isResolved={thread.isResolved}
        line={thread.line}
        path={thread.path}
        rightSideContent={
          <IconButton
            aria-label={thread.isResolved ? 'Unresolve conversation' : 'Resolve conversation'}
            tooltipDirection="sw"
            icon={thread.isResolved ? CheckCircleFillIcon : CheckCircleIcon}
            // need to be specific in order to override default IconButton color
            sx={{color: thread.isResolved ? 'var(--fgColor-done, var(--color-done-fg)) !important' : undefined}}
            variant="invisible"
            onClick={thread.isResolved ? handleUnresolveThread : handleResolveThread}
          />
        }
        onNavigateToDiffComment={onNavigateToDiffComment}
        onToggleCollapsed={onToggleCollapsed}
        threadId={thread.threadId}
      />
      {errorMessage && (
        <Flash variant="danger" className="m-2">
          <StopIcon className="mr-2" />
          {errorMessage}
        </Flash>
      )}
    </>
  )
}
