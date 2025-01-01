import {useMemo} from 'react'

import {groupChatMessages} from '../components/ChatMessagesGroup'
import type {CopilotChatState} from '../utils/copilot-chat-reducer'
import {getActiveMessages} from '../utils/copilot-chat-subthreading-helpers'
import {type CopilotChatMessage, NullMessageId} from '../utils/copilot-chat-types'

export function useGroupedMessages(state: CopilotChatState) {
  const {streamingMessage, isWaitingOnCopilot, messages: completedMessages, selectedThreadID} = state

  const messages = useMemo(() => {
    const nullMessage: CopilotChatMessage = {
      id: NullMessageId,
      role: 'assistant',
      content: '',
      createdAt: '',
      threadID: selectedThreadID || '',
      references: [],
      clientSide: true,
      messageIndex: -1,
    }

    const activeMessages = getActiveMessages(completedMessages)

    if (isWaitingOnCopilot) {
      return [...activeMessages, streamingMessage ?? nullMessage]
    }

    return activeMessages
  }, [completedMessages, streamingMessage, isWaitingOnCopilot, selectedThreadID])

  return {messages, groupedMessages: groupChatMessages(messages)}
}
