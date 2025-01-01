import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {useAlive} from '@github-ui/use-alive'

export function useSharedThreadChannel() {
  const {selectedThreadID, sharedThreadChannel} = useChatState()
  const manager = useChatManager()

  const handleSharedThreadEvent = () => {
    void manager.fetchSharedThreadMessages(selectedThreadID)
  }

  useAlive(sharedThreadChannel, handleSharedThreadEvent)
}
