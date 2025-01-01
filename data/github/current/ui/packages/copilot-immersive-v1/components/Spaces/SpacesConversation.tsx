import type {CustomCopilotId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {useRef} from 'react'

import {useHandleMessageSubmit} from '../../hooks/use-handle-message-submit'
import {ErrorFallback} from '../ErrorFallback'
import {SpaceDetailsPage} from './SpaceDetailsPage'
import {SpacesHeader} from './SpacesHeader'

interface SpacesConversationProps {
  selectedThreadID: string | null
  customCopilotId: CustomCopilotId
  textAreaRef: React.RefObject<HTMLTextAreaElement>
}

export function SpacesConversation({customCopilotId, selectedThreadID, textAreaRef}: SpacesConversationProps) {
  const state = useChatState()
  const {messages} = state

  const currentTopicRef = useRef(state.currentTopic)
  const nextMessageIndex = messages.length

  const handleUserSubmit = useHandleMessageSubmit(currentTopicRef, nextMessageIndex)

  return (
    <>
      <SpacesHeader />
      <ErrorBoundary fallback={<ErrorFallback regionName="This space" />}>
        <SpaceDetailsPage
          customCopilotId={customCopilotId}
          onChatSubmit={handleUserSubmit}
          selectedThreadID={selectedThreadID}
          textAreaRef={textAreaRef}
        />
      </ErrorBoundary>
    </>
  )
}
