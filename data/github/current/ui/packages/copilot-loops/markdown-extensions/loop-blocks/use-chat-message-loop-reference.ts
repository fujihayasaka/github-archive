import {useChatMessage} from '@github-ui/copilot-chat/components/ChatMessageContext'
import {getLoopFromChatMessage} from '../../utils/chat-helpers'

export function useChatMessageLoopReference() {
  const {message} = useChatMessage()
  const loopData = getLoopFromChatMessage(message)
  return loopData?.pipeline ?? null
}
