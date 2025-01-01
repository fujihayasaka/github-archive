import {srOnlyHeader} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {
  CopilotChatMessage,
  CopilotChatReference,
  TextReference,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {CheckIcon, LinkIcon, RepoForkedIcon} from '@primer/octicons-react'
import {useEffect} from 'react'

import {ChatMessageReferences} from './ChatMessageReferences'
import {makeVersionedItemFromReference} from './ContentPreview/content-preview-types'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'
import {MarkdownViewer} from './MarkdownViewer'
import styles from './TimelineEvents.module.css'

type TimelineEvent = 'switch-issue-template' | 'issue-created' | 'link-sub-issue' | 'unlink-sub-issue'

type TimelineEventContent = {
  type: TimelineEvent
  markdownContent: string
}

type TimelineEventContentJSON =
  `{"type": "${TimelineEventContent['type']}", "markdownContent": "${TimelineEventContent['markdownContent']}"}`

export interface TimelineEventTextReference extends TextReference {
  name: `timeline-event: ${TimelineEventContentJSON}`
}

function isTimelineReference(ref: CopilotChatReference): ref is TimelineEventTextReference {
  return ref.type === 'text' && ref.name != null && ref.name.startsWith('timeline-event:')
}

export function userMessageIsTimelineEvent(message: CopilotChatMessage): boolean {
  return message.references?.some(isTimelineReference) ?? false
}

export type TimelineEventsProps = {
  message: CopilotChatMessage
  messageIndex: number
  isViewingSharedThread: boolean
  isSharedMessage?: boolean
  isLatestMessage?: boolean
}
export function TimelineEvents({
  message,
  messageIndex,
  isViewingSharedThread,
  isSharedMessage,
  isLatestMessage,
}: TimelineEventsProps) {
  /*
    There are two types of timeline events: a user message, and a situational message.

    - User messages: messages with specific reference names are timeline events. These messages don't
      go through the normal ChatMessage component; instead, we render them here as a timeline event.

    - Situational messages: some messages trigger a timeline event if they meet certain critera (ex: a shared message)
  */
  return (
    <>
      {userMessageIsTimelineEvent(message) && (
        <UserMessageTimelineEvent message={message} messageIndex={messageIndex} />
      )}
      <SituationalTimelineEvents
        isViewingSharedThread={isViewingSharedThread}
        isSharedMessage={isSharedMessage}
        isLatestMessage={isLatestMessage}
      />
    </>
  )
}

type UserMessageTimelineEventProps = {
  message: CopilotChatMessage
  messageIndex: number
}
function UserMessageTimelineEvent({message, messageIndex}: UserMessageTimelineEventProps) {
  // Certain references are used for versioning (Files, Issues, etc.)
  // Usually, processing these references happens in the ChatMessage, but for UserMessageTimelineEvents,
  // we don't render the ChatMessage. So, make sure these references / versions are processed:
  const {updateItem} = useContentPreview()
  useEffect(() => {
    if (message.references) {
      for (const ref of message.references) {
        const item = makeVersionedItemFromReference({
          ref,
          messageIndex,
          messageId: message.id,
          timestamp: message.createdAt,
        })
        if (item != null) updateItem(item)
      }
    }
  }, [message.references, message.id, messageIndex, message.createdAt, updateItem])

  const timelineReferences = message.references?.filter(ref => isTimelineReference(ref))
  if (!timelineReferences) return

  const timelineEvents: TimelineEventContent[] = []
  for (const timelineReference of timelineReferences) {
    const content = JSON.parse(timelineReference.name.replace('timeline-event: ', ''))
    timelineEvents.push(content as TimelineEventContent)
  }

  return (
    <>
      {message.references && message.references.length > 0 && (
        <ChatMessageReferences
          className={styles.references}
          messageId={message.id}
          messageTimestamp={message.createdAt}
          messageIndex={messageIndex}
          references={message.references}
          size="medium"
        />
      )}

      {timelineEvents.map(timelineEvent => (
        <div className={styles.timelineEvent} key={timelineEvent.type}>
          <CheckIcon className={styles.icon} />
          <MarkdownViewer
            autoOpenPreviewPane={false}
            markdown={timelineEvent.markdownContent}
            messageId={message.id}
            messageIndex={messageIndex}
            messageTimestamp={message.createdAt}
            accessibleHeader={srOnlyHeader('Timeline', message.content ?? '')}
          />
        </div>
      ))}
    </>
  )
}

type SituationalTimelineEventsProps = {
  isSharedMessage?: boolean
  isViewingSharedThread?: boolean
  isLatestMessage?: boolean
}
function SituationalTimelineEvents({
  isSharedMessage,
  isViewingSharedThread,
  isLatestMessage,
}: SituationalTimelineEventsProps) {
  return (
    <>
      {isSharedMessage && !isViewingSharedThread && (
        <div className={styles.situationalTimelineEvent}>
          <LinkIcon className={styles.icon} /> Messages up to this point are included in shared link
        </div>
      )}

      {isLatestMessage && copilotFeatureFlags.copilotDuplicateThread && isViewingSharedThread && (
        <div className={styles.situationalTimelineEvent}>
          <RepoForkedIcon className={styles.icon} /> Messages beyond this point will start a new private conversation
        </div>
      )}
    </>
  )
}
