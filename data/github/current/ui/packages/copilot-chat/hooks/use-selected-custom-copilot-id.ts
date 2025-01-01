import type {CustomCopilotId} from '../utils/copilot-chat-types'
import {customCopilotIdFromThread, useRouteSpaceId} from '../utils/custom-copilots-helpers'
import {useSelectedThread} from '../utils/use-selected-thread'

/**
 * Pulls the selected custom copilot (space) from either the URL or the selected thread per the chat state.
 */
export function useSelectedCustomCopilotId(): CustomCopilotId | null {
  const thread = useSelectedThread()
  return useRouteSpaceId() || customCopilotIdFromThread(thread)
}
