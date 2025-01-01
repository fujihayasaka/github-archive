import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {COPILOT_PATH} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useTrackingRef} from '@github-ui/use-tracking-ref'
import {useEffect, useRef} from 'react'
import {useNavigate} from 'react-router-dom'

import type {CopilotImmersivePayload} from '../routes/payloads'

/**
 * If the chat state manager changes the thread ID (ie, by creating a new thread), update the route to match accordingly.
 */
function useSyncRouteToThreadState() {
  const {selectedThreadID} = useChatState()
  // If we depend on `useNavigate` directly, it will run every time we change routes, but before the routing completes.
  // This will cause an infinite loop of state updates as we keep trying to navigate back and forth.
  const navigateRef = useTrackingRef(useNavigate())

  useEffect(() => {
    // selectedThreadID can be null if no thread is created yet. In this case we can leave them at the current URL
    // (typically /copilot)
    if (!selectedThreadID) return

    const threadPath = `${COPILOT_PATH}/c/${selectedThreadID}`
    if (!window.location.pathname.startsWith(threadPath)) navigateRef.current(threadPath)
  }, [navigateRef, selectedThreadID])
}

/**
 * If the route changes (ie, by navigation), tell the manager to fetch the new thread.
 */
function useSyncThreadStateToRoute() {
  const {threadID: threadId} = useRoutePayload<CopilotImmersivePayload>()
  const firstRun = useRef(true)
  const lastThreadId = useRef<string | null>(null)
  const manager = useChatManager()
  const {threads, selectedThreadID} = useChatState()

  // Initial page load
  useEffect(() => {
    void manager.fetchMessages(selectedThreadID)
    // NOTE: we only want to fetch messages on the initial page load
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Subsequent navigations
  useEffect(() => {
    if (firstRun.current) {
      firstRun.current = false
      lastThreadId.current = threadId
      return
    }

    if (lastThreadId.current !== threadId) {
      lastThreadId.current = threadId

      if (threadId === selectedThreadID) return // already selected

      const thread = threadId && threads?.get(threadId)
      void manager.selectThread(thread || null, {includeThreads: false, clearTopic: true})
    }
  }, [manager, threadId, threads, selectedThreadID])
}

function useHandleBackNavigation() {
  const manager = useChatManager()

  useEffect(() => {
    const onPopState = () => {
      if (window.location.href.includes('/r/')) {
        // the browser back/forward button was used to nav to a repo topic url
        // hide the topic picker and clear the selected thread.
        manager.showTopicPicker(false)
        void manager.selectThread(null)
      } else if (!window.location.href.includes('/c/')) {
        // the browser back/forward button was used to nav to immersive landing page
        // show the topic picker and clear the selected thread.
        manager.showTopicPicker(true)
        void manager.selectThread(null)
      }
    }
    window.addEventListener('popstate', onPopState)
    return () => {
      window.removeEventListener('popstate', onPopState)
    }
  }, [manager])
}

export function useRoutedThreads() {
  useSyncThreadStateToRoute()
  useSyncRouteToThreadState()
  useHandleBackNavigation()
}
