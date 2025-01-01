import {CheckCircleFillIcon, CheckCircleIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {Tooltip} from '@primer/react/next'

import {usePullRequestToolbarAnalytics} from '../hooks/use-pull-request-toolbar-analytics'
import {ConversationHeader} from './ConversationHeader'

interface ThreadHeaderData {
  id: string
  isOutdated: boolean
  isResolved: boolean
  line?: number | null
  path: string
}

type ThreadHeaderProps = {
  isCollapsed: boolean
  onNavigateToDiffThread: () => void
  onToggleCollapsed: () => void
  thread: ThreadHeaderData
}

export function ThreadHeader({isCollapsed, onToggleCollapsed, onNavigateToDiffThread, thread}: ThreadHeaderProps) {
  const {sendPullRequestAnalyticsEvent} = usePullRequestToolbarAnalytics()

  const handleResolveThread = () => {
    // TODO: Add mutation to resolve a thread
    if (!isCollapsed) onToggleCollapsed()

    sendPullRequestAnalyticsEvent('comments.resolve_thread', 'RESOLVE_CONVERSATION_BUTTON')
  }

  const handleUnresolveThread = () => {
    // TODO: Add mutation to unresolve a thread
    if (!isCollapsed) onToggleCollapsed()

    sendPullRequestAnalyticsEvent('comments.unresolve_thread', 'RESOLVE_CONVERSATION_BUTTON')
  }

  return (
    <ConversationHeader
      isCollapsed={isCollapsed}
      isOutdated={thread.isOutdated}
      isResolved={thread.isResolved}
      line={thread.line}
      path={thread.path}
      rightSideContent={
        <Tooltip
          direction="sw"
          id="resolve-conversation"
          text={thread.isResolved ? 'Unresolve conversation' : 'Resolve conversation'}
          type="label"
        >
          {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
          <IconButton
            aria-labelledby="resolve-conversation"
            icon={thread.isResolved ? CheckCircleFillIcon : CheckCircleIcon}
            // need to be specific in order to override default IconButton color
            sx={{color: thread.isResolved ? 'var(--fgColor-done, var(--color-done-fg)) !important' : undefined}}
            unsafeDisableTooltip
            variant="invisible"
            onClick={thread.isResolved ? handleUnresolveThread : handleResolveThread}
          />
        </Tooltip>
      }
      onNavigateToDiffThread={onNavigateToDiffThread}
      onToggleCollapsed={onToggleCollapsed}
    />
  )
}
