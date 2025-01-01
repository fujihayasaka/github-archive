import {ThreadOptionButton} from '@github-ui/copilot-chat/components/Header'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {COPILOT_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {DialogType} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useNavigate} from '@github-ui/use-navigate'

export interface ThreadHeaderMenuProps {
  setShowStaffDialog: (value: DialogType) => void
}

export const ThreadHeaderMenu = (props: ThreadHeaderMenuProps) => {
  const {selectedThreadID, threads, mode} = useChatState()
  const manager = useChatManager()
  const navigate = useNavigate()

  const thread = selectedThreadID ? threads.get(selectedThreadID) : null

  const handleDelete = () => {
    if (thread) {
      void manager.deleteThread(thread)
    }

    if (mode === 'immersive') {
      navigate(COPILOT_PATH)
    }
  }

  return (
    <ThreadOptionButton handleDelete={handleDelete} setShowStaffDialog={props.setShowStaffDialog} thread={thread} />
  )
}
