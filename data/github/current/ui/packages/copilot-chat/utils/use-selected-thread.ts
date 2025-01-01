import type {CopilotChatThread} from './copilot-chat-types'
import {useChatStateValues} from './CopilotChatContext'
import {getSelectedThread} from './get-selected-thread'

export function useSelectedThread(): CopilotChatThread | null {
  const state = useChatStateValues('selectedThreadID', 'threads')
  return getSelectedThread(state)
}
