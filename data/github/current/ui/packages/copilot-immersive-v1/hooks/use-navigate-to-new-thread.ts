import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {COPILOT_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {SelectThreadOptions} from '@github-ui/copilot-chat/utils/copilot-chat-manager'
import {useCallback} from 'react'

/**
 * Navigate to the new thread page. This works by pushing a new history entry to the browser history rather
 * than using React Router's navigation.
 */
export function useNavigateToNewThread() {
  const manager = useChatManager()
  return useCallback(
    async (newThreadOptions?: SelectThreadOptions) => {
      if (window.location.pathname === COPILOT_PATH) {
        if (newThreadOptions?.customCopilotId === undefined) {
          // clear space ID if user is on an empty space thread and clicks on 'general conversation'
          manager.dispatch({type: 'SET_CUSTOM_COPILOT_ID', customCopilotId: null})
        }

        return
      }

      history.pushState(history.state, '', COPILOT_PATH)
      manager.dispatch({type: 'SELECT_PLUGIN', plugin: null})
      await manager.selectThread(null, newThreadOptions)
    },
    [manager],
  )
}
