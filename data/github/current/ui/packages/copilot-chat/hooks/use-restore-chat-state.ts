import safeStorage from '@github-ui/safe-storage'
import {useEffect} from 'react'

import type {CopilotChatMessage, CopilotChatMode, CopilotChatThread} from '../utils/copilot-chat-types'

const sessionStorage = safeStorage('sessionStorage')

interface PreservedChatState {
  expiry: number
  restoredMessages: CopilotChatMessage[]
  threadId: string
  threadTitle: string | undefined | null
}

const RESTORED_CHAT_STATE_EXPIRY = 1000 * 8 // 8 seconds

/**
 * No need to restore chat state if we're in immersive mode, and if there's no thread id, there can't be any messages to restore.
 */
function shouldRestoreChatState(threadId: string | null, mode: CopilotChatMode) {
  return !!threadId && mode === 'assistive'
}

const RESTORED_CHAT_DATA_KEY = 'restored-chat-messages'

/**
 * Adds event listeners to save the chat state to session storage when the user navigates between GitHub pages.
 * This is used to restore the chat state so we don't show the user a loading spinner whenever
 * a hard navigation takes place.
 */
export function useSaveChatState(
  messages: CopilotChatMessage[],
  threadId: string | null,
  threads: Map<string, CopilotChatThread>,
  mode: CopilotChatMode,
) {
  const restoreChatState = shouldRestoreChatState(threadId, mode)

  useEffect(() => {
    if (!restoreChatState) return

    const replacer = (key: string, value: unknown) => {
      // Thread messages have circular references. Remove them from serialization, they will be regenerated when loading state.
      if (key === 'childMessages' || key === 'parentMessage') return undefined
      else return value
    }

    const onUnloadChat = () => {
      if (!messages?.length || !threadId) return
      const thread = threads.get(threadId)
      const threadTitle = thread?.name

      const state: PreservedChatState = {
        expiry: Date.now() + RESTORED_CHAT_STATE_EXPIRY,
        restoredMessages: messages,
        threadId,
        threadTitle,
      }

      sessionStorage.setItem(RESTORED_CHAT_DATA_KEY, JSON.stringify(state, replacer))
    }

    // handles turbo navigations
    window.addEventListener('turbo:before-fetch-response', onUnloadChat)

    // handles page refresh
    window.addEventListener('beforeunload', onUnloadChat)

    // handles back/forward navigation
    window.addEventListener('popstate', onUnloadChat)

    return () => {
      window.removeEventListener('turbo:before-fetch-response', onUnloadChat)
      window.removeEventListener('beforeunload', onUnloadChat)
      window.removeEventListener('popstate', onUnloadChat)
    }
  }, [messages, restoreChatState, threadId, threads])
}

/**
 * Parse the restored chat state from session storage and return it if it's valid.
 */
export function useRestoredChatState(
  threadId: string | null,
  mode: CopilotChatMode,
): {restoredMessages?: CopilotChatMessage[] | undefined; restoredThreadTitle?: string | undefined | null} {
  const restoreChatState = shouldRestoreChatState(threadId, mode)

  const restoredChatState = sessionStorage.getItem(RESTORED_CHAT_DATA_KEY)
  const parsedState = restoredChatState ? (JSON.parse(restoredChatState) as PreservedChatState) : undefined

  useEffect(() => {
    // Clear out the restored chat state when the component mounts.
    // This state is only used to populate the chat reducer's initial state.
    sessionStorage.removeItem(RESTORED_CHAT_DATA_KEY)
  }, [])

  if (restoreChatState && parsedState?.expiry && parsedState.expiry > Date.now() && parsedState.threadId === threadId) {
    return {restoredMessages: parsedState.restoredMessages, restoredThreadTitle: parsedState.threadTitle}
  }

  return {}
}
