import {ChatInput as SharedChatInput} from '@github-ui/copilot-chat/components/ChatInput'
import {useCallback, type RefObject} from 'react'
import {usePipesDispatch} from '../../contexts/PipesStateProvider'
import {useAppContext} from '../../contexts/AppContextProvider'
import {useChatStateLens} from '@github-ui/copilot-chat/CopilotChatContext'
import {sendEvent} from '@github-ui/hydro-analytics'

interface ChatInputProps {
  textAreaRef: RefObject<HTMLTextAreaElement>
}

export function ChatInput({textAreaRef}: ChatInputProps) {
  const dispatch = usePipesDispatch()
  const {sendChatMessage} = useAppContext()
  const streamingMessage = useChatStateLens(s => s.streamingMessage)

  const handleUserSubmit = useCallback(
    async (content: string) => {
      sendEvent('dotcom_chat.activate', {target: 'PANEL_CHAT_MESSAGE_SUBMIT', mode: 'loops'})
      sendChatMessage(content)
      dispatch({type: 'FOCUS_NODE', nodeId: null})
    },
    [sendChatMessage, dispatch],
  )

  return (
    <SharedChatInput
      textAreaRef={textAreaRef}
      onSubmit={handleUserSubmit}
      placeholder="Refine your loop"
      size="large"
      isStreaming={!!streamingMessage}
      hideAttachmentButton
    />
  )
}
