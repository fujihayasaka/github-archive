import {useDerivedObservable, useObservableValue, useObservedState} from '@github-ui/react-observable'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type {PropsWithChildren} from 'react'
import {createContext, useContext, useReducer} from 'react'
import {RelayEnvironmentProvider} from 'react-relay'

import {useRestoredChatState, useSaveChatState} from '../hooks/use-restore-chat-state'
import {isRepository} from './copilot-chat-helpers'
import type {CopilotChatAction, CopilotChatState} from './copilot-chat-reducer'
import {copilotChatReducer} from './copilot-chat-reducer'
import type {
  CopilotChatAgent,
  CopilotChatMessage,
  CopilotChatMode,
  CopilotChatOrg,
  CopilotChatReference,
  CopilotChatRepo,
  CopilotChatThread,
} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'
import {copilotLocalStorage} from './copilot-local-storage'
import {CopilotChatAutocompleteProvider} from './CopilotChatAutocompleteContext'
import {CopilotChatManagerProvider} from './CopilotChatManagerContext'
import {DEFAULT_MODEL} from './models'
import {ObservableChatStateProvider, useObservableChatStateContext} from './ObservableChatContext'

export const ChatPanelReferenceContext = createContext<React.RefObject<HTMLDivElement> | null>(null)
const CopilotChatDispatchContext = createContext<React.Dispatch<CopilotChatAction> | null>(null)

export interface CopilotChatProviderProps {
  apiURL: string
  login: string
  topic?: CopilotChatRepo
  threadId: string | null
  workerPath: string
  refs: CopilotChatReference[]
  selectedReference?: CopilotChatReference | null
  mode: CopilotChatMode
  ssoOrganizations: CopilotChatOrg[]
  renderKnowledgeBases?: boolean
  renderAttachKnowledgeBaseHerePopover?: boolean
  renderKnowledgeBaseAttachedToChatPopover?: boolean
  customInstructions?: string
  chatIsOpen?: boolean
  chatIsVisible?: boolean
  chatVisibleSettingPath?: string
  renderBetaLabel?: boolean
  agentsPath: string
  optedInToUserFeedback: boolean
  agents?: CopilotChatAgent[]
  messages?: CopilotChatMessage[]
  testReducerState?: CopilotChatState
  reviewLab: boolean
  scrollToTop?: boolean
  realIp?: string
  currentView?: 'thread' | 'list'
  hasCEorCBAccess?: boolean
}

export function CopilotChatProvider({
  children,
  topic,
  login,
  apiURL,
  workerPath,
  threadId,
  refs,
  selectedReference,
  mode,
  ssoOrganizations,
  renderKnowledgeBases,
  renderAttachKnowledgeBaseHerePopover,
  renderKnowledgeBaseAttachedToChatPopover,
  customInstructions,
  chatIsOpen,
  chatIsVisible,
  chatVisibleSettingPath,
  renderBetaLabel,
  agentsPath,
  optedInToUserFeedback,
  agents,
  messages,
  testReducerState,
  reviewLab,
  scrollToTop,
  realIp,
  currentView,
  hasCEorCBAccess,
}: PropsWithChildren<CopilotChatProviderProps>) {
  const {restoredMessages, restoredThreadTitle} = useRestoredChatState(threadId, mode)

  const initialState = testReducerState || {
    threadsLoading: {state: 'pending', error: null},
    messagesLoading: {state: 'pending', error: null},
    messagesRestored: !!restoredMessages,
    slashCommandLoading: {state: 'pending', error: null},
    showTopicPicker:
      !(copilotFeatureFlags.copilotImmersiveV1 && mode === 'immersive') &&
      (!threadId || mode === 'assistive') &&
      !topic,
    topicLoading: {state: 'pending', error: null},
    threads: new Map<string, CopilotChatThread>(),
    restoredThreadTitle,
    knowledgeBasesLoading: {state: 'pending', error: null},
    knowledgeBases: [],
    model: DEFAULT_MODEL,
    availableModels: [DEFAULT_MODEL],
    modelsLoading: {state: 'pending', error: null},
    messages: messages ?? restoredMessages ?? [],
    streamer: null,
    streamingMessage: null,
    selectedThreadID: threadId,
    currentTopic: topic,
    chatIsOpen: Boolean(chatIsOpen),
    isWaitingOnCopilot: false,
    currentUserLogin: login,
    apiUrl: apiURL,
    currentReferences: refs,
    findFileWorkerPath: workerPath,
    currentView: currentView || 'thread',
    selectedReference: selectedReference ?? null,
    mode,
    currentRepository: isRepository(topic) ? topic : undefined,
    ssoOrganizations,
    context: undefined,
    renderKnowledgeBases: renderKnowledgeBases ?? true,
    renderAttachKnowledgeBaseHerePopover,
    renderKnowledgeBaseAttachedToChatPopover,
    customInstructions,
    chatIsVisible,
    chatVisibleSettingPath,
    renderBetaLabel,
    topRepositoriesCache: undefined,
    agentsPath,
    optedInToUserFeedback,
    agents,
    suggestionsDismissed: false,
    reviewLab,
    scrollToTop,
    repoCustomInstructionsEnabled: copilotLocalStorage.getRepoCustomInstructionsState(),
  }

  const [state, dispatch] = useReducer(copilotChatReducer, initialState)
  useSaveChatState(state.messages, state.selectedThreadID, state.threads, state.mode)

  const environment = relayEnvironmentWithMissingFieldHandlerForNode()

  return (
    <ChatStateProvider state={state}>
      <CopilotChatDispatchContext.Provider value={dispatch}>
        <CopilotChatManagerProvider
          apiURL={apiURL}
          state={state}
          dispatch={dispatch}
          ssoOrganizations={ssoOrganizations}
          realIp={realIp}
          hasCEorCBAccess={hasCEorCBAccess}
        >
          <CopilotChatAutocompleteProvider>
            <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
          </CopilotChatAutocompleteProvider>
        </CopilotChatManagerProvider>
      </CopilotChatDispatchContext.Provider>
    </ChatStateProvider>
  )
}

const ChatStateContext = createContext<CopilotChatState | null>(null)

export function ChatStateProvider({state, children}: PropsWithChildren<{state: CopilotChatState}>) {
  // A constant reference to an Observable
  const stateObservable = useObservableValue(state)

  // When the state updates, update the value of the observable
  useLayoutEffect(() => {
    // eslint-disable-next-line react-compiler/react-compiler
    stateObservable.value = state
  }, [state, stateObservable])

  return (
    <ObservableChatStateProvider value={stateObservable}>
      <ChatStateContext.Provider value={state}>{children}</ChatStateContext.Provider>
    </ObservableChatStateProvider>
  )
}

/**
 * Returns the current version of the chat state.
 * This causes the component to re-render any time there is an update to any part of the state.
 * Our goal is to deprecate and remove this hook.
 *
 * @example
 * ```ts
 * const {messages, customInstructions} = useChatState()
 * ```
 */
export function useChatState(): CopilotChatState {
  const chatState = useContext(ChatStateContext)
  if (!chatState) throw new Error('useChatState can only be used inside a CopilotChatProvider')
  return chatState
}

/**
 * Returns the result of the lens function applied to the chat state.
 * This causes the component to re-render whenever the given function results in a new value.
 * The lens function must always be pure.
 *
 * @example
 * ```ts
 * const hasMessages = useChatStateLens(s => s.messages.length > 0)
 * ```
 */
export function useChatStateLens<T>(lens: (state: CopilotChatState) => T): T {
  const o = useObservableChatStateContext()
  if (!o) throw new Error('useChatStateLens can only be used inside a CopilotChatProvider')
  const valueObservable = useDerivedObservable(o, lens)
  return useObservedState(valueObservable)
}

/**
 * Returns the current value of `state[key]` on the `CopilotChatState`.
 * This causes the component to re-render whenever that property has a new value.
 *
 * @example
 * ```ts
 * const model = useChatStateValue('model')
 * ```
 */
export function useChatStateValue<T extends keyof CopilotChatState>(key: T): CopilotChatState[T] {
  return useChatStateLens(s => s[key])
}

/**
 * Returns a subset of the `CopilotChatState` containing only the specified keys.
 * This causes the component to re-render whenever a property corresponding to one of those keys has a new value.
 *
 * @example
 * ```ts
 * const {model, availableModels} = useChatStateValues('model', 'availableModels')
 * ```
 */
export function useChatStateValues<TKey extends keyof CopilotChatState = never>(
  ...keys: TKey[]
): Pick<CopilotChatState, TKey> {
  return useChatStateLens(s => getSubsetFromState(s, keys))
}

function getSubsetFromState<TObject extends object, TKey extends keyof TObject>(
  state: TObject,
  keys: TKey[],
): Pick<TObject, TKey> {
  const out = {} as unknown as Pick<TObject, TKey>
  for (const key of keys) {
    out[key] = state[key]
  }
  return out
}

export function useChatDispatch(): React.Dispatch<CopilotChatAction> {
  const dispatch = useContext(CopilotChatDispatchContext)
  if (!dispatch) throw new Error('useChatDispatch can only be used inside a CopilotChatProvider')
  return dispatch
}

export function useChatPanelReferenceContext(): React.RefObject<HTMLDivElement> | null {
  return useContext(ChatPanelReferenceContext)
}
