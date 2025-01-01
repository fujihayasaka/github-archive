import type {ObservableValue} from '@github-ui/observable'
import {createContext, useCallback, useContext} from 'react'

import type {CopilotChatState} from './copilot-chat-reducer'

const ObservableChatStateContext = createContext<ObservableValue<CopilotChatState> | null>(null)
export const ObservableChatStateProvider = ObservableChatStateContext.Provider

/**
 * Returns a constant reference to a function that can be used inside a callback to get the current version of the chat state.
 *
 * The returned `getChatState()` function should only be used inside an event handler or callback. If it is used in a render
 * method, it may return outdated state.
 */
export function useGetChatState(): () => CopilotChatState {
  const o = useContext(ObservableChatStateContext)
  if (!o) throw new Error('useGetChatState can only be used inside a CopilotChatProvider')
  return useCallback(() => o.value, [o])
}

export function useObservableChatStateContext() {
  return useContext(ObservableChatStateContext)
}
