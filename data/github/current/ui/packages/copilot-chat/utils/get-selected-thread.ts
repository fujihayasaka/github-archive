import type {CopilotChatState} from './copilot-chat-reducer'
import type {CopilotChatThread} from './copilot-chat-types'

export function getSelectedThread(
  state: Pick<CopilotChatState, 'selectedThreadID' | 'threads'>,
): CopilotChatThread | null {
  if (!state.selectedThreadID) return null
  return state.threads.get(state.selectedThreadID) || null
}
