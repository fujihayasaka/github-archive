import {debounce} from '@github/mini-throttle'
import type {Dispatch, PropsWithChildren} from 'react'
import {createContext, useContext, useEffect, useMemo} from 'react'

import {useEntitlement} from '../components/quota/EntitlementContext'
import {usePlugins} from '../plugin/ImmersivePluginsProvider'
import {CopilotChatManager} from './copilot-chat-manager'
import type {CopilotChatAction, CopilotChatState} from './copilot-chat-reducer'
import type {CopilotChatOrg} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'
import {copilotLocalStorage} from './copilot-local-storage'
import {useGetChatState} from './ObservableChatContext'

const CopilotChatManagerContext = createContext<CopilotChatManager | null>(null)

export interface CopilotChatManagerProviderProps {
  apiURL: string
  state: CopilotChatState
  dispatch: Dispatch<CopilotChatAction>
  ssoOrganizations: CopilotChatOrg[]
  realIp?: string
  hasCEorCBAccess?: boolean
  apiVersion?: string
}

export function CopilotChatManagerProvider({
  apiURL,
  state,
  dispatch,
  ssoOrganizations,
  children,
  realIp,
  hasCEorCBAccess,
  apiVersion,
}: PropsWithChildren<CopilotChatManagerProviderProps>) {
  const getChatState = useGetChatState()
  const plugins = usePlugins()
  const manager = useMemo(
    () =>
      new CopilotChatManager(
        dispatch,
        apiURL,
        ssoOrganizations,
        getChatState,
        realIp,
        undefined,
        hasCEorCBAccess,
        plugins,
        apiVersion,
      ),
    [dispatch, apiURL, ssoOrganizations, getChatState, realIp, hasCEorCBAccess, plugins, apiVersion],
  )
  const {licenseType} = useEntitlement()

  useEffect(() => {
    if (!state.chatIsOpen || copilotFeatureFlags.topicsAsReferences) return

    const fetchCurrentTopic = async () => {
      if (state.selectedThreadID && state.messages.length > 0 && !state.currentTopic) {
        const currentThreadTopic = copilotLocalStorage.getSelectedTopic(state.selectedThreadID)
        const numberId = Number(currentThreadTopic)
        if (currentThreadTopic && !isNaN(numberId)) {
          await manager.fetchCurrentRepo(numberId)
        } else {
          manager.clearCurrentTopic()
        }
      }
    }
    void fetchCurrentTopic()
  }, [state.selectedThreadID, manager, state.messages.length, state.currentTopic, state.chatIsOpen])

  useEffect(() => {
    const controller = new AbortController()
    const fetchContextPage = async () => {
      const hash = window.location.hash
      const pathName = window.location.pathname
      const url = window.location.hash ? `${pathName}${hash}` : pathName
      const urlParts = url.slice(1).split('/')
      if (urlParts.length < 2) {
        return
      }

      const owner = urlParts[0]
      const repo = urlParts[1]

      if (!owner || !repo) {
        return
      }

      await manager.fetchImplicitContext(url, owner, repo)
    }

    const voidFetch = () => {
      void fetchContextPage()
    }

    const debouncedFetch = debounce(voidFetch, 500)

    function watchHistoryEvents() {
      // eslint-disable-next-line @typescript-eslint/unbound-method, no-restricted-properties
      const {replaceState, pushState} = window.history

      // eslint-disable-next-line no-restricted-properties
      window.history.replaceState = function (...args) {
        // eslint-disable-next-line no-restricted-properties
        replaceState.apply(window.history, args)

        // Chat suggestions are based on the current page context. Since fetching a new context is
        // an async (and debounced) call, clear any existing suggestions first to reduce flicker.
        manager.clearSuggestions()

        window.dispatchEvent(new Event('replaceState'))
      }

      // pushState is called by the browser when the user navigates to a new page. We need to listen
      // for this event to clear and generates suggestions.
      // eslint-disable-next-line no-restricted-properties
      window.history.pushState = function (...args) {
        // eslint-disable-next-line no-restricted-properties
        pushState.apply(window.history, args)

        // Chat suggestions are based on the current page context. Since fetching a new context is
        // an async (and debounced) call, clear any existing suggestions first to reduce flicker.
        manager.clearSuggestions()

        window.dispatchEvent(new Event('pushState'))
      }

      window.addEventListener('popstate', debouncedFetch, {signal: controller.signal})
      window.addEventListener('replaceState', debouncedFetch, {signal: controller.signal})
      window.addEventListener('pushState', debouncedFetch, {signal: controller.signal})
    }

    if (state.chatIsOpen) {
      debouncedFetch()
      watchHistoryEvents()
    }
    return () => {
      controller.abort()
    }
  }, [manager, state.chatIsOpen, licenseType])

  return <CopilotChatManagerContext.Provider value={manager}>{children}</CopilotChatManagerContext.Provider>
}

export function useChatManager() {
  const context = useContext(CopilotChatManagerContext)
  if (!context) {
    throw new Error('useChatManager must be used within a CopilotChatManagerProvider')
  }
  return context
}
