import {useEffect, useRef} from 'react'

import {isDocset} from '../utils/copilot-chat-helpers'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {copilotLocalStorage} from '../utils/copilot-local-storage'
import {useChatState} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'

export function useChat(inputRef?: React.RefObject<HTMLTextAreaElement>) {
  const state = useChatState()
  const manager = useChatManager()
  const {currentTopic, messages, selectedThreadID} = state
  const thread = manager.getSelectedThread(state)
  const chatTextAreaRef = useRef<HTMLTextAreaElement>(null)
  const textAreaRef = inputRef || chatTextAreaRef

  useEffect(() => {
    if (thread && messages.length > 0) {
      manager.showTopicPicker(false)
    }
  }, [thread, messages.length, manager])

  useEffect(() => {
    const topicID = currentTopic ? (isDocset(currentTopic) ? currentTopic.name : String(currentTopic.id)) : null
    if (selectedThreadID && topicID) {
      copilotLocalStorage.setSelectedTopic(selectedThreadID, topicID)
    }
  }, [selectedThreadID, currentTopic])

  useEffect(() => {
    const timeout = window.setTimeout(() => {
      textAreaRef.current?.focus()
    }, 1)
    return () => {
      window.clearTimeout(timeout)
    }
  }, [textAreaRef])

  useEffect(() => {
    const generateSuggestions = async () => {
      if (!copilotFeatureFlags.staticThreadSuggestions) return

      const suggestionContext = state.context?.[0] ?? state.currentTopic
      if (!suggestionContext) return

      await manager.generateSuggestions(suggestionContext, state.selectedThreadID)
    }

    void generateSuggestions()

    return () => {
      manager.clearSuggestions()
    }
  }, [manager, state.context, state.currentTopic, state.selectedThreadID])

  return {textAreaRef}
}
