import {AttachmentsProvider} from '@github-ui/attachments'
import {useDerivedObservable, useObservableValue, useObservedState} from '@github-ui/react-observable'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type {PropsWithChildren} from 'react'
import {createContext, useContext, useEffect, useReducer} from 'react'
import {RelayEnvironmentProvider} from 'react-relay'

import {EntitlementProvider} from '../components/quota/EntitlementContext'
import {useRestoredChatState, useSaveChatState} from '../hooks/use-restore-chat-state'
import type {CopilotChatAction, CopilotChatState} from './copilot-chat-reducer'
import {copilotChatReducer} from './copilot-chat-reducer'
import {constructMessagesHierarchy} from './copilot-chat-subthreading-helpers'
import type {
  CopilotChatAgent,
  CopilotChatMessage,
  CopilotChatMode,
  CopilotChatOrg,
  CopilotChatPayload,
  CopilotChatReference,
  CopilotChatRepo,
  CopilotChatThread,
  CustomCopilot,
} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'
import {CopilotImageAttacher} from './copilot-image-attacher'
import {copilotLocalStorage} from './copilot-local-storage'
import {CopilotChatAutocompleteProvider} from './CopilotChatAutocompleteContext'
import {CopilotChatManagerProvider} from './CopilotChatManagerContext'
import {DEFAULT_MODEL} from './models'
import {ObservableChatStateProvider, useObservableChatStateContext} from './ObservableChatContext'

const environment = relayEnvironmentWithMissingFieldHandlerForNode()

const CopilotChatDispatchContext = createContext<React.Dispatch<CopilotChatAction> | null>(null)

export interface CopilotChatProviderProps {
  topic?: CopilotChatRepo
  threadId: string | null
  copilotSpaceId?: string | null
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
}

export function CopilotChatProvider({
  children,
  topic,
  workerPath,
  threadId,
  copilotSpaceId,
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

  if (restoredMessages && copilotFeatureFlags.immersiveSubthreading) {
    restoredMessages = constructMessagesHierarchy(restoredMessages)
  }

  const topicAsReference: CopilotChatReference | undefined = topic ? {...topic, type: 'repository'} : undefined

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
    model: DEFAULT_MODEL,
    availableModels: [DEFAULT_MODEL],
    modelsLoading: {state: 'pending', error: null},
    messages: messages ?? restoredMessages ?? [],
    streamingMessage: null,
    selectedThreadID: threadId,
    currentTopic: copilotFeatureFlags.topicsAsReferences ? undefined : topic,
    chatIsOpen: Boolean(chatIsOpen),
    isWaitingOnCopilot: false,
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
    optedInToPreviewFeatures: copilotChatPayload.optedInToPreviewFeatures,
    optedInToUserFeedback: copilotChatPayload.optedInToUserFeedback,
    agents,
    customCopilots,
    customCopilotId: null,
    activePlugin: pluginId ?? undefined,
    reviewLab: copilotChatPayload.reviewLab,
    repoCustomInstructionsEnabled: copilotLocalStorage.getRepoCustomInstructionsState(),
    isEditorUpsellBannerDismissed: copilotUpsellBannerDismissed,
    ambientError: undefined,
    personalInstructions: copilotChatPayload.personalInstructions ?? null,
    threadHasNewMessages: false,
  }

  const [state, dispatch] = useReducer(copilotChatReducer, initialState)
  useSaveChatState(state.messages, state.selectedThreadID, state.threads, state.mode)

  // Update the custom copilot ID when the URL changes
  useEffect(() => {
    if (copilotSpaceId) {
      const number = Number(copilotSpaceId)
      if (!isNaN(number)) dispatch({type: 'SET_CUSTOM_COPILOT_ID', customCopilotId: number})
    }
  }, [copilotSpaceId])

  return (
    <EntitlementProvider initialLicenseType={copilotChatPayload.licenseType} initialQuotas={copilotChatPayload.quotas}>
      <ChatStateProvider state={state}>
        <CopilotChatDispatchContext.Provider value={dispatch}>
          <CopilotChatManagerProvider
            apiURL={copilotChatPayload.apiURL}
            state={state}
            dispatch={dispatch}
            ssoOrganizations={ssoOrganizations}
            realIp={realIp}
            hasCEorCBAccess={copilotChatPayload.hasCEorCBAccess}
          >
            <CopilotChatAutocompleteProvider>
              <RelayEnvironmentProvider environment={environment}>
                <AttachmentsProvider
                  attachLimit={CopilotImageAttacher.getAttachmentLimit()}
                  fileSizeLimit={CopilotImageAttacher.getAttachmentSizeLimit()}
                >
                  {children}
                </AttachmentsProvider>
              </RelayEnvironmentProvider>
            </CopilotChatAutocompleteProvider>
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
