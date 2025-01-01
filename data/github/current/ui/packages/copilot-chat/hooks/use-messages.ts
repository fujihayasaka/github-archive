import {useFocusZone} from '@primer/react'
import {useEffect, useMemo, useRef, useState} from 'react'

import type {CopilotChatMessage} from '../utils/copilot-chat-types'
import {useChatState} from '../utils/CopilotChatContext'

export function useMessages(
  isWaitingOnCopilot: boolean,
  messages: CopilotChatMessage[],
  onMessageReceived: ({forceScroll}: {forceScroll?: boolean}) => void,
) {
  const state = useChatState()
  const [focusZoneEnabled, setFocusZoneEnabled] = useState(true)
  const focusableElements = useRef<HTMLElement[]>([])

  const memoizedDependencies = useMemo(
    () => ({
      messages,
      isWaitingOnCopilot,
    }),
    [messages, isWaitingOnCopilot],
  )

  const {containerRef} = useFocusZone(
    {
      focusInStrategy: () => {
        const activeElement = document.activeElement as HTMLElement
        return focusableElements.current.includes(activeElement)
          ? activeElement
          : focusableElements.current[focusableElements.current.length - 1]
      },
      focusableElementFilter: element => {
        // if has class `message-container`
        if (element.classList.contains('message-container')) {
          if (!focusableElements.current.includes(element)) {
            focusableElements.current.push(element)
          }
          return true
        }
        return false
      },
      disabled: !focusZoneEnabled,
    },
    [memoizedDependencies],
  )

  const latestMessage = state.streamingMessage ?? messages[messages.length - 1]
  const lastLatestMessageId = useRef(latestMessage?.id)
  const lastReferenceCount = useRef(state.currentReferences.length)
  const hasSuggestionsRef = useRef(!!state.suggestions)

  // Scroll all the way to the bottom when:
  // - This component first loads
  // - A new message is posted
  // - A new reference is added
  // - The content of the latest message changes (i.e. streaming is happening) and the scroll position is at the bottom.
  // - Follow up suggestions have been added after streaming completes
  useEffect(() => {
    if (
      lastLatestMessageId.current !== latestMessage?.id ||
      lastReferenceCount.current < state.currentReferences.length ||
      latestMessage?.error?.isError ||
      (!hasSuggestionsRef.current && !!state.suggestions)
    ) {
      onMessageReceived({forceScroll: true})
      lastLatestMessageId.current = latestMessage?.id
      hasSuggestionsRef.current = !!state.suggestions
    } else {
      onMessageReceived({forceScroll: false})
    }
    lastReferenceCount.current = state.currentReferences.length
  }, [
    latestMessage?.id,
    latestMessage?.content,
    latestMessage?.error,
    onMessageReceived,
    state.currentReferences,
    state.suggestions,
  ])

  return {
    containerRef,
    setFocusZoneEnabled,
  }
}
