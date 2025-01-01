import {useDerivedObservable, useObservableValue, useObservedState} from '@github-ui/react-observable'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type {PropsWithChildren} from 'react'
import {createContext, useContext, useEffect, useReducer} from 'react'

import {EntitlementProvider} from '../components/quota/EntitlementContext'
import {useRestoredChatState, useSaveChatState} from '../hooks/use-restore-chat-state'
import {makeRepositoryReference} from './copilot-chat-helpers'
import type {CopilotChatAction, CopilotChatState} from './copilot-chat-reducer'
import {copilotChatReducer} from './copilot-chat-reducer'
import {constructMessagesHierarchy} from './copilot-chat-subthreading-helpers'
import type {
  CopilotChatAgent,
  CopilotChatMessage,
  CopilotChatMode,
  CopilotChatModel,
  CopilotChatOrg,
  CopilotChatPayload,
  CopilotChatReference,
  CopilotChatRepo,
  CopilotChatThread,
  CustomCopilot,
  RepositoryReference,
} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'
import {copilotLocalStorage} from './copilot-local-storage'
import {CopilotChatManagerProvider} from './CopilotChatManagerContext'
import {getDefaultModel} from './models'
import {ObservableChatStateProvider, useObservableChatStateContext} from './ObservableChatContext'

const CopilotChatDispatchContext = createContext<React.Dispatch<CopilotChatAction> | null>(null)

export interface CopilotChatProviderProps {
  topic?: CopilotChatRepo
  threadId: string | null
  pluginId?: string | null
  workerPath: string
  refs: CopilotChatReference[]
  selectedReference?: CopilotChatReference | null
  mode: CopilotChatMode
  ssoOrganizations: CopilotChatOrg[]
  chatIsOpen?: boolean
  chatIsVisible?: boolean
  chatVisibleSettingPath?: string
  agents?: CopilotChatAgent[]
  customCopilots?: CustomCopilot[]
  messages?: CopilotChatMessage[]
  testReducerState?: CopilotChatState
  realIp?: string
  currentView?: 'thread' | 'list'
  copilotUpsellBannerDismissed?: boolean
  copilotChatPayload: CopilotChatPayload
  wrapCodeLines?: boolean
}

export function CopilotChatProvider({
  children,
  topic,
  workerPath,
  threadId,
  pluginId,
  refs,
  selectedReference,
  mode,
  ssoOrganizations,
  chatIsOpen,
  chatIsVisible,
  chatVisibleSettingPath,
  agents,
  customCopilots,
  messages,
  testReducerState,
  realIp,
  currentView,
  copilotUpsellBannerDismissed,
  copilotChatPayload,
}: PropsWithChildren<CopilotChatProviderProps>) {
  const restoredChatState = useRestoredChatState(threadId, mode)
  let restoredMessages = restoredChatState.restoredMessages
  const restoredThreadTitle = restoredChatState.restoredThreadTitle

  if (restoredMessages) {
    restoredMessages = constructMessagesHierarchy(restoredMessages)
  }

  const topicAsReference: RepositoryReference | undefined = topic ? makeRepositoryReference(topic) : undefined
  const defaultModel: CopilotChatModel = getDefaultModel(null, null)

  const initialState: CopilotChatState = testReducerState || {
    threadsLoading: {state: 'pending', error: null},
    messagesLoading: {state: 'pending', error: null},
    messagesRestored: !!restoredMessages,
    slashCommandLoading: {state: 'pending', error: null},
    showTopicPicker: mode !== 'immersive' && (!threadId || mode === 'assistive') && !topic,
    topicLoading: {state: 'pending', error: null},
    threads: new Map<string, CopilotChatThread>(),
    restoredThreadTitle,
    knowledgeBasesLoading: {state: 'pending', error: null},
    knowledgeBases: [],
    model: defaultModel,
    availableModels: [defaultModel],
    modelsLoading: {state: 'pending', error: null},
    messages: messages ?? restoredMessages ?? [],
    streamingMessage: null,
    selectedThreadID: threadId,
    currentTopic: copilotFeatureFlags.topicsAsReferences ? undefined : topic,
    chatIsOpen: Boolean(chatIsOpen),
    isWaitingOnCopilot: false,
    isWaitingOnAttachment: false,
    currentUserLogin: copilotChatPayload.currentUserLogin,
    apiUrl: copilotChatPayload.apiURL,
    currentReferences: copilotFeatureFlags.topicsAsReferences && topicAsReference ? [topicAsReference, ...refs] : refs,
    findFileWorkerPath: workerPath,
    currentView: currentView || 'thread',
    selectedReference: selectedReference ?? null,
    mode,
    currentRepository: topic,
    ssoOrganizations,
    context: undefined,
    renderKnowledgeBases: copilotChatPayload.renderKnowledgeBases ?? true,
    renderAttachKnowledgeBaseHerePopover: copilotChatPayload.renderAttachKnowledgeBaseHerePopover,
    renderKnowledgeBaseAttachedToChatPopover: copilotChatPayload.renderKnowledgeBaseAttachedToChatPopover,
    customInstructions: copilotChatPayload.customInstructions,
    chatIsVisible,
    chatVisibleSettingPath,
    renderBetaLabel: copilotChatPayload.renderBetaLabel,
    topRepositoriesCache: undefined,
    agentsPath: copilotChatPayload.agentsPath,
    customCopilotsEnabled: copilotChatPayload.customCopilotsEnabled ?? false,
    optedInToPreviewFeatures: copilotChatPayload.optedInToPreviewFeatures,
    optedInToUserFeedback: copilotChatPayload.optedInToUserFeedback,
    agents,
    customCopilots,
    activePlugin: pluginId ?? undefined,
    reviewLab: copilotChatPayload.reviewLab,
    repoCustomInstructionsEnabled: copilotLocalStorage.getRepoCustomInstructionsState(),
    isEditorUpsellBannerDismissed: copilotUpsellBannerDismissed,
    ambientError: undefined,
    personalInstructions: copilotChatPayload.personalInstructions ?? null,
    threadHasNewMessages: false,
    sharedThreadsLoading: {state: 'pending', error: null},
    skillOptions: {
      deepCodeSearch: false,
    },
    wrapCodeLines: copilotLocalStorage.getWrapCodeLines(),
    sharedThreadChannel: copilotChatPayload.sharedThreadChannel,
    autoSubmit: copilotChatPayload.autoSubmit ?? false,
  }

  const [state, dispatch] = useReducer(copilotChatReducer, initialState)
  useSaveChatState(state.messages, state.selectedThreadID, state.threads, state.mode)

  useEffect(
    function saveCurrentReferences() {
      if (!state.chatIsOpen) return

      const referencesWithoutCurrentRepo = state.currentReferences.filter(
        r => r.type !== 'repository' || r.id !== state.currentRepository?.id,
      )
      copilotLocalStorage.setCurrentReferences(state.selectedThreadID, referencesWithoutCurrentRepo)
    },
    [state.selectedThreadID, state.currentReferences, state.currentRepository, state.chatIsOpen],
  )

  return (
    <EntitlementProvider
      initialLicenseType={copilotChatPayload.licenseType}
      initialPlan={copilotChatPayload.plan}
      initialQuotas={copilotChatPayload.quotas}
    >
      <ChatStateProvider state={state}>
        <CopilotChatDispatchContext.Provider value={dispatch}>
          <CopilotChatManagerProvider
            apiURL={copilotChatPayload.apiURL}
            apiVersion={copilotChatPayload.apiVersion}
            state={state}
            dispatch={dispatch}
            ssoOrganizations={ssoOrganizations}
            realIp={realIp}
            hasCEorCBAccess={copilotChatPayload.hasCEorCBAccess}
          >
            {children}
          </CopilotChatManagerProvider>
        </CopilotChatDispatchContext.Provider>
      </ChatStateProvider>
    </EntitlementProvider>
  )
}

const ChatStateContext = createContext<CopilotChatState | null>(null)

export function ChatStateProvider({state, children}: PropsWithChildren<{state: CopilotChatState}>) {
  // A constant reference to an Observable
  const stateObservable = useObservableValue(state)

  // When the state updates, update the value of the observable
  useLayoutEffect(() => {
    // eslint-disable-next-line react-hooks/react-compiler
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
