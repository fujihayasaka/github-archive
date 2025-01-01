import {useEffect} from 'react'

import type {CopilotChatMessage} from '../utils/copilot-chat-types'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatScroll} from './ChatScrollContainer'

interface ChatMessagesGroupProps {
  isLastGroup: boolean
  children: React.ReactNode
}

export const ChatMessagesGroup = ({isLastGroup, children}: ChatMessagesGroupProps) => {
  const {scrollContainerHeight, scrollToBottom} = useChatScroll()
  // When we restore an old thread or change subthreads, we don't clear the screen. We only do that when a message is
  // sent, edited, or retried - when the user is expecting a response from Copilot
  const {threadHasNewMessages} = useChatState()
  const fillViewport = isLastGroup && threadHasNewMessages

  useEffect(() => {
    if (fillViewport) scrollToBottom('smooth')
  }, [fillViewport, scrollToBottom])

  return <div style={fillViewport ? {minHeight: scrollContainerHeight} : undefined}>{children}</div>
}

type NotEmptyArray<T> = [T, ...T[]]

/** Each group is a set of user requests followed by assistant responses. */
export function groupChatMessages(messages: CopilotChatMessage[]): CopilotChatMessage[][] {
  return messages.reduce<Array<NotEmptyArray<CopilotChatMessage>>>((groups, message) => {
    const lastGroup = groups.at(-1)
    const lastRole = lastGroup?.at(-1)?.role ?? 'assistant'

    // every time the role changes from assistant to user, create a new group
    if (lastRole === 'assistant' && message.role === 'user') groups.push([message])
    else lastGroup?.push(message)

    return groups
  }, [])
}
