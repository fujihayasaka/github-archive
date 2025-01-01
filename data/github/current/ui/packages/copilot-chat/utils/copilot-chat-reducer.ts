import {sendEvent, stringifyObjectValues} from '@github-ui/hydro-analytics'

import type {CopilotChatEntitlement} from './copilot-chat-entitlement'
import {
  findAuthor,
  isDocset,
  makeRepositoryReference,
  referenceArraysAreEqual,
  referenceID,
  referencesAreEqual,
} from './copilot-chat-helpers'
import {
  addMessageToHierarchy,
  constructMessagesHierarchy,
  getActiveMessages,
  selectActiveMessage,
  unselectPreviousChild,
} from './copilot-chat-subthreading-helpers'
import type {
  CopilotAgentConfirmation,
  CopilotAgentError,
  CopilotAnnotations,
  CopilotChatAgent,
  CopilotChatMessage,
  CopilotChatMessageFeedback,
  CopilotChatMode,
  CopilotChatModel,
  CopilotChatOrg,
  CopilotChatReference,
  CopilotChatRepo,
  CopilotChatSuggestions,
  CopilotChatThread,
  CustomCopilot,
  Docset,
  FunctionCalledStatus,
  MessageStreamingResponseComplete,
  SkillExecution,
  ToolCallRequest,
  TopicItem,
} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'
import {copilotLocalStorage} from './copilot-local-storage'
import type {DotcomFileAttachment} from './uploadable-file-attachment'

export type Dispatcher = (value: CopilotChatAction) => void

export type LoadingStateState = 'pending' | 'loading' | 'loaded' | 'error'
type LoadingState = {
  state: LoadingStateState
  error: string | null
}
export interface CopilotChatState {
  threadsLoading: LoadingState
  messagesLoading: LoadingState & {missingOrgIds?: number[]; notFound?: boolean}
  messagesRestored: boolean
  slashCommandLoading: LoadingState
  showTopicPicker: boolean
  topicLoading: LoadingState
  threads: Map<string, CopilotChatThread>
  restoredThreadTitle?: string | undefined | null
  messages: CopilotChatMessage[]
  streamingMessage: CopilotChatMessage | null
  selectedThreadID: string | null
  /** Have any messages been sent since opening this thread? */
  threadHasNewMessages: boolean
  model: CopilotChatModel
  availableModels: CopilotChatModel[] | null
  modelsLoading: LoadingState
  currentTopic?: CopilotChatRepo
  chatIsOpen: boolean
  isWaitingOnCopilot: boolean
  currentUserLogin: string
  apiUrl: string
  currentReferences: CopilotChatReference[]
  selectedReference: CopilotChatReference | null
  findFileWorkerPath: string
  currentView: 'thread' | 'list'
  mode: CopilotChatMode
  activePlugin?: string
  currentRepository?: CopilotChatRepo
  ssoOrganizations: CopilotChatOrg[]
  context?: CopilotChatReference[]
  renderKnowledgeBases?: boolean
  renderAttachKnowledgeBaseHerePopover?: boolean
  renderKnowledgeBaseAttachedToChatPopover?: boolean
  chatIsVisible?: boolean
  chatVisibleSettingPath?: string
  renderBetaLabel?: boolean
  customInstructions?: string
  topRepositoriesCache: TopicItem[] | undefined
  entryPointId?: string
  suggestions?: CopilotChatSuggestions | null
  agents?: CopilotChatAgent[]
  agentsPath?: string
  customCopilots?: CustomCopilot[]
  customCopilotId?: number | null
  optedInToPreviewFeatures: boolean
  optedInToUserFeedback: boolean
  /** when set, messages default to being sent to this agent */
  defaultRecipient?: string
  allClientConfirmations?: string[]
  knowledgeBasesLoading: LoadingState
  knowledgeBases: Docset[]
  reviewLab: boolean
  entitlement?: CopilotChatEntitlement
  repoCustomInstructionsEnabled: boolean
  isEditorUpsellBannerDismissed?: boolean
  ambientError?: AmbientError | null
  personalInstructions: string | null
  lastActiveMessageId?: string
  elementMap?: Map<string, Element>
  clientSkillsRequest?: ToolCallRequest[]
  clientSkillConfirmation?: CopilotAgentConfirmation
  action?: string
}

export interface AmbientError {
  message: string
}

export interface Timings {
  /** The time the request started */
  startTime: number
  /** The time the first message was received */
  firstByte?: number
  /** The time the first content token was received */
  firstToken?: number
  /** The time the request completed */
  endTime: number
}

export type CopilotChatAction =
  | {type: 'OPEN_COPILOT_CHAT'; source: string; id?: string}
  | {type: 'CLOSE_COPILOT_CHAT'}
  | {type: 'HIDE_COPILOT_CHAT'}
  | {
      type: 'MESSAGES_UPDATED'
      messages?: CopilotChatMessage[]
      state: LoadingStateState
      missingOrgIds?: number[]
      notFound?: boolean
    }
  | {type: 'SELECT_THREAD'; thread: CopilotChatThread | null; clearTopic?: boolean; customCopilotId?: number | null}
  | {type: 'THREADS_LOADING'}
  | {type: 'THREADS_LOADING_ERROR'; message: string}
  | {type: 'HANDLE_EVENT_START'; references?: CopilotChatReference[]; id?: string}
  | {type: 'THREAD_CREATED'; thread: CopilotChatThread}
  | {type: 'THREAD_CONTINUED'; thread: CopilotChatThread}
  | {type: 'WAITING_ON_COPILOT'; loading: boolean}
  | {type: 'DELETE_THREAD'; thread: CopilotChatThread}
  | {type: 'DELETE_THREAD_KEEP_SELECTION'; thread: CopilotChatThread}
  | {type: 'DELETE_ALL_THREADS_KEEP_SELECTION'; threads: CopilotChatThread[]}
  | {type: 'DELETE_THREAD_ERROR'; thread: CopilotChatThread; error: string}
  | {type: 'DELETE_ALL_THREADS_ERROR'; threads: CopilotChatThread[]; error: string}
  | {type: 'CLEAR_THREAD'; threadID: string}
  | {type: 'CLEAR_REFERENCES'; threadID: string}
  | {type: 'CLEAR_CURRENT_REFERENCES'; shouldNotClear?: string[]}
  | {type: 'KNOWLEDGE_BASES_LOADING'}
  | {type: 'KNOWLEDGE_BASES_LOADED'; knowledgeBases: Docset[]}
  | {type: 'KNOWLEDGE_BASES_LOADING_ERROR'; message: string}
  | {type: 'THREADS_LOADED'; threads: CopilotChatThread[]}
  | {type: 'LATEST_THREAD_LOADED'; latestThread: CopilotChatThread}
  | {
      type: 'MESSAGE_ADDED'
      message: CopilotChatMessage
      repoHasCustomInstructions?: boolean
      usedRepoCustomInstructions?: boolean
    }
  | {
      type: 'MESSAGE_FEEDBACK'
      message: CopilotChatMessage
      feedback: CopilotChatMessageFeedback
    }
  | {
      type: 'MESSAGES_SET_SELECTED_MESSAGE'
      message: CopilotChatMessage
    }
  | {
      type: 'MESSAGES_UNSELECT_PREVIOUS_MESSAGE'
      message: CopilotChatMessage
    }
  | {type: 'THREAD_UPDATED'; thread: CopilotChatThread}
  | {type: 'REFERENCES_LOADED'; references: CopilotChatReference[]}
  | {type: 'ADD_REFERENCE'; reference: CopilotChatReference; source: string}
  | {type: 'REMOVE_REFERENCES'; references: CopilotChatReference[]}
  | {type: 'SLASH_COMMANDS_LOADING'}
  | {type: 'SLASH_COMMANDS_LOADED'}
  | {type: 'SLASH_COMMANDS_ERROR'}
  | {type: 'SHOW_TOPIC_PICKER'; show: boolean}
  | {type: 'CURRENT_TOPIC_UPDATED'; topic: CopilotChatRepo | undefined; state: LoadingStateState}
  | {type: 'MESSAGE_STREAMING_STARTED'; message: CopilotChatMessage}
  | {type: 'MESSAGE_STREAMING_TOKEN_ADDED'; token: string}
  | {
      type: 'MESSAGE_STREAMING_FUNCTION_CALLED'
      name: string
      status: FunctionCalledStatus
      arguments?: string
      errorMessage?: string
      references: CopilotChatReference[]
    }
  | {type: 'CLIENT_SKILL_CONFIRMATION_REQUEST'; confirmation: CopilotAgentConfirmation | undefined}
  | {type: 'CLIENT_SKILLS_REQUEST'; toolCalls: ToolCallRequest[]}
  | {
      type: 'MESSAGE_STREAMING_COMPLETED'
      messageResponse: MessageStreamingResponseComplete
      timings: Timings
    }
  | {type: 'MESSAGE_STREAMING_FAILED'; timings: Timings}
  | {type: 'MESSAGE_STREAMING_STOPPED'; timings: Timings}
  | {type: 'MESSAGES_CLEAR_LAST_ERROR'}
  | {type: 'SELECT_REFERENCE'; reference: CopilotChatReference | null}
  | {type: 'MODELS_LOADING'}
  | {type: 'MODELS_LOADING_ERROR'; error: string}
  | {type: 'MODELS_LOADED'; models: CopilotChatModel[]}
  | {type: 'SELECT_MODEL'; model: CopilotChatModel}
  | {type: 'VIEW_ALL_THREADS'}
  | {type: 'VIEW_CURRENT_THREAD'}
  | {type: 'IMPLICIT_CONTEXT_UPDATED'; context: CopilotChatReference[] | undefined}
  | {type: 'DISMISS_ATTACH_KNOWLEDGE_BASE_HERE_POPOVER'}
  | {type: 'DISMISS_KNOWLEDGE_BASE_ATTACHED_TO_CHAT_POPOVER'}
  | {type: 'SET_TOP_REPOSITORIES'; topics: TopicItem[] | undefined}
  | {type: 'SUGGESTIONS_GENERATED'; suggestions: CopilotChatSuggestions | null}
  | {type: 'CLEAR_SUGGESTIONS'}
  | {type: 'SET_AGENTS'; agents: CopilotChatAgent[]}
  | {type: 'SET_CUSTOM_COPILOT'; customCopilot: CustomCopilot}
  | {type: 'SET_CUSTOM_COPILOTS'; customCopilots: CustomCopilot[]}
  | {type: 'SET_CUSTOM_COPILOT_ID'; customCopilotId: number | null}
  | {type: 'DELETE_COPILOT_SPACE'; copilot: CustomCopilot}
  | {type: 'DELETE_COPILOT_SPACE_ERROR'; copilot: CustomCopilot; error: string}
  | {
      type: 'MESSAGE_STREAMING_CONFIRMATION'
      title: string
      message: string
      confirmation: object
    }
  | {type: 'AGENT_ERROR'; error: CopilotAgentError}
  | {type: 'ENTITLEMENT_UPDATED'; entitlement: CopilotChatEntitlement | undefined}
  | {type: 'TOGGLE_REPO_CUSTOM_INSTRUCTIONS'; value: boolean}
  | {type: 'DISMISS_EDITOR_UPSELL_BANNER'}
  | {type: 'DISMISS_AMBIENT_ERROR'}
  | {type: 'ADD_AMBIENT_ERROR'; message: string}
  | {type: 'SET_PERSONAL_INSTRUCTIONS'; personalInstructions: string | null}
  | {type: 'READ_DOM_SKILL_INVOKED'; elementMap: Map<string, Element>}
  | {type: 'SELECT_PLUGIN'; plugin: string | null | undefined}
  | {type: 'SHARED_THREAD_UPDATED'; thread: CopilotChatThread}
  | {type: 'IMAGE_UPLOADED'; referenceId: string; dotcomAttachment: DotcomFileAttachment}

export const copilotChatReducer = (state: CopilotChatState, action: CopilotChatAction): CopilotChatState => {
  const setSelectedThreadID = (
    selectedThreadID: string | null,
    customCopilotId: number | null = null,
  ): CopilotChatState => {
    if (selectedThreadID) copilotLocalStorage.selectedThreadID = selectedThreadID

    const isNewSelectedThread = selectedThreadID !== state.selectedThreadID

    const modelID = copilotLocalStorage.getModel(selectedThreadID)?.id
    const model = state.availableModels?.find(m => m.id === modelID) ?? state.model

    return {
      ...state,
      model,
      selectedThreadID,
      currentView: 'thread',
      showTopicPicker: selectedThreadID ? false : state.showTopicPicker,
      customCopilotId,
      currentReferences: isNewSelectedThread ? [] : state.currentReferences,
      threadHasNewMessages: isNewSelectedThread ? false : state.threadHasNewMessages,
    }
  }

  const setSelectedCopilotSpace = (customCopilotId: number | null): CopilotChatState => {
    return {
      ...state,
      customCopilotId,
    }
  }

  const setCurrentReferences = (currentReferences: CopilotChatReference[]): CopilotChatState => {
    copilotLocalStorage.setCurrentReferences(state.selectedThreadID, currentReferences)
    return {...state, currentReferences}
  }

  switch (action.type) {
    case 'SLASH_COMMANDS_ERROR': {
      sendEvent('copilot.slash_commands_error')
      return {
        ...state,
        slashCommandLoading: {...state.slashCommandLoading, state: 'error'},
      }
    }
    case 'SLASH_COMMANDS_LOADED': {
      sendEvent('copilot.slash_commands_loaded')
      return {
        ...state,
        slashCommandLoading: {...state.slashCommandLoading, state: 'loaded'},
      }
    }
    case 'SLASH_COMMANDS_LOADING': {
      return {
        ...state,
        slashCommandLoading: {...state.slashCommandLoading, state: 'loading'},
      }
    }
    case 'OPEN_COPILOT_CHAT':
      sendEvent('copilot.open_copilot_chat', {source: action.source})
      return {
        ...state,
        chatIsOpen: true,
        chatIsVisible: true,
        entryPointId: action.id,
      }
    case 'CLOSE_COPILOT_CHAT':
      sendEvent('copilot.close_copilot_chat')
      return {
        ...state,
        chatIsOpen: false,
      }
    case 'HIDE_COPILOT_CHAT':
      sendEvent('copilot.hide_copilot_chat')
      return {
        ...state,
        chatIsVisible: false,
      }
    case 'THREAD_CREATED':
      sendEvent('copilot.thread_created', {
        ...stringifyThread(action.thread),
        mode: state.mode,
        count: state.threads.size + 1,
      })
      return {
        ...setSelectedThreadID(action.thread.id, action.thread.customCopilotID),
        threads: new Map(state.threads.set(action.thread.id, action.thread)),
      }
    case 'THREAD_CONTINUED':
      sendEvent('copilot.thread_continued', {
        ...stringifyThread(action.thread),
        mode: state.mode,
        count: state.threads.size + 1,
      })
      return {
        ...setSelectedThreadID(action.thread.id, action.thread.customCopilotID),
        threads: new Map(state.threads.set(action.thread.id, action.thread)),
      }
    case 'SUGGESTIONS_GENERATED':
      return {
        ...state,
        suggestions: action.suggestions,
      }
    case 'CLEAR_SUGGESTIONS':
      return {
        ...state,
        suggestions: null,
      }
    case 'CLEAR_THREAD':
      sendEvent('copilot.clear_thread')
      return {
        ...state,
        messages: [],
        currentReferences: [],
      }
    case 'CLEAR_REFERENCES':
      return {
        ...state,
        currentReferences: state.currentReferences.filter(
          // these are the references we want to keep after sending a message
          reference => reference.type === 'docset' || reference.type === 'magic-knowledge-base',
        ),
      }
    case 'CLEAR_CURRENT_REFERENCES': {
      sendEvent('copilot.clear_current_references')
      let currentRefs: CopilotChatReference[] = []
      const {shouldNotClear} = action

      if (shouldNotClear) {
        currentRefs = state.currentReferences.filter(reference => {
          if (shouldNotClear.includes('image') && reference.type === 'image') {
            return copilotFeatureFlags.attachImagesImmersive
          }
          return shouldNotClear.includes(reference.type)
        })
      }

      return {
        ...state,
        currentReferences: currentRefs,
        action: 'CLEAR_CURRENT_REFERENCES',
      }
    }
    case 'MESSAGES_UPDATED': {
      let messages = action.messages ? [...action.messages] : []
      if (action.state === 'error') {
        sendEvent('copilot.messages_updated', {count: action.messages?.length, loading: action.state})
      }
      if (messages) {
        let defaultRecipient = state.defaultRecipient
        let allClientConfirmations = state.allClientConfirmations
        if (action.state === 'loaded' && messages.length > 0) {
          defaultRecipient = getDefaultRecipient(messages[messages.length - 1]!, state)
          allClientConfirmations = messages
            .map(
              message => message.clientConfirmations?.map(cc => JSON.stringify(Object.values(cc.confirmation).sort())),
            )
            .flat()
            .filter(Boolean) as string[]
        }

        // Messages that came from server are not client-side by definition
        for (const message of messages) {
          message.clientSide = false
        }

        if (copilotFeatureFlags.immersiveSubthreading) {
          messages = constructMessagesHierarchy(messages)
        }
        return {
          ...state,
          defaultRecipient,
          allClientConfirmations,
          messages,
          messagesLoading: {
            ...state.messagesLoading,
            state: action.state,
            missingOrgIds: action.missingOrgIds,
            notFound: action.notFound,
          },
          messagesRestored: false,
        }
      } else {
        return {
          ...state,
          messagesLoading: {
            ...state.messagesLoading,
            state: action.state,
            missingOrgIds: action.missingOrgIds,
            notFound: action.notFound,
          },
        }
      }
    }
    case 'WAITING_ON_COPILOT':
      return {
        ...state,
        isWaitingOnCopilot: action.loading,
        threadHasNewMessages: true,
      }
    case 'SELECT_THREAD': {
      const customCopilotId = action.customCopilotId || action.thread?.customCopilotID || null

      sendEvent('copilot.select_thread', {
        threadID: action.thread?.id,
        mode: state.mode,
        customCopilotId,
      })

      const result: CopilotChatState = {
        ...setSelectedThreadID(action.thread?.id || null, customCopilotId),
        currentTopic: action.clearTopic ? undefined : state.currentTopic,
        topicLoading: action.clearTopic ? {error: null, state: 'loaded'} : state.topicLoading,
      }

      // Reset the references to the current repo if navigating to a new thread. Otherwise, keep the value that comes
      // from setSelectedThreadID, which resets the references on navigating across threads
      if (action.thread === null && state.currentRepository && copilotFeatureFlags.topicsAsReferences) {
        result.currentReferences = [makeRepositoryReference(state.currentRepository)]
      }

      return result
    }
    case 'HANDLE_EVENT_START': {
      sendEvent('copilot.handle_event_start')
      const newState = action.references ? setCurrentReferences(action.references) : state
      return {
        ...newState,
        chatIsOpen: true,
        chatIsVisible: true,
        entryPointId: action.id,
      }
    }
    case 'THREADS_LOADING':
      return {
        ...state,
        threadsLoading: {...state.threadsLoading, state: 'loading'},
      }
    case 'DISMISS_ATTACH_KNOWLEDGE_BASE_HERE_POPOVER':
      sendEvent('copilot.dismiss_attach_knowledge_base_here_popover')
      return {
        ...state,
        renderAttachKnowledgeBaseHerePopover: false,
      }
    case 'DISMISS_KNOWLEDGE_BASE_ATTACHED_TO_CHAT_POPOVER':
      sendEvent('copilot.dismiss_knowledge_base_attached_to_chat_popover')
      return {
        ...state,
        renderKnowledgeBaseAttachedToChatPopover: false,
      }
    case 'KNOWLEDGE_BASES_LOADING':
      return {
        ...state,
        knowledgeBasesLoading: {...state.knowledgeBasesLoading, state: 'loading'},
      }
    case 'KNOWLEDGE_BASES_LOADED':
      sendEvent('copilot.knowledge_bases_loaded', {count: action.knowledgeBases.length})
      return {
        ...state,
        knowledgeBases: action.knowledgeBases,
        knowledgeBasesLoading: {...state.knowledgeBasesLoading, state: 'loaded', error: null},
      }
    case 'KNOWLEDGE_BASES_LOADING_ERROR':
      sendEvent('copilot.knowledge_bases_loading_error', {error: action.message})
      return {
        ...state,
        knowledgeBasesLoading: {...state.knowledgeBasesLoading, state: 'error', error: action.message},
      }
    case 'LATEST_THREAD_LOADED':
      return {
        ...state,
        threads: new Map(state.threads.set(action.latestThread.id, action.latestThread)),
      }
    case 'THREADS_LOADED':
      sendEvent('copilot.threads_loaded', {count: action.threads.length, mode: state.mode})
      return {
        ...state,
        threadsLoading: {...state.threadsLoading, state: 'loaded'},
        threads: new Map(action.threads.map(t => [t.id, t])),
      }
    case 'THREADS_LOADING_ERROR':
      sendEvent('copilot.threads_loading_error', {error: action.message})
      return {
        ...state,
        threadsLoading: {error: action.message, state: 'error'},
      }
    case 'DELETE_THREAD_KEEP_SELECTION':
      sendEvent('copilot.thread_deleted', {
        ...stringifyThread(action.thread),
        count: state.threads.size - 1,
      })
      state.threads.delete(action.thread.id)
      return {
        ...setSelectedThreadID(null),
        threads: new Map(state.threads),
        threadsLoading: {...state.threadsLoading, state: 'loaded'},
        messages: [],
        messagesLoading: {state: 'loaded', error: null},
        currentReferences: [],
        currentView: 'list',
      }
    case 'DELETE_ALL_THREADS_KEEP_SELECTION':
      for (const thread of action.threads) {
        sendEvent('copilot.thread_deleted', {
          ...stringifyThread(thread),
          count: state.threads.size - 1,
        })
        state.threads.delete(thread.id)
      }
      return {
        ...setSelectedThreadID(null),
        threads: new Map(state.threads),
        threadsLoading: {...state.threadsLoading, state: 'loaded'},
        messages: [],
        messagesLoading: {state: 'loaded', error: null},
        currentReferences: [],
        currentView: 'list',
      }
    case 'DELETE_THREAD':
      sendEvent('copilot.thread_deleted', {
        ...stringifyThread(action.thread),
        count: state.threads.size - 1,
        mode: state.mode,
      })
      state.threads.delete(action.thread.id)
      if (state.selectedThreadID === action.thread.id) {
        return {
          ...setSelectedThreadID(null),
          threads: new Map(state.threads),
          threadsLoading: {...state.threadsLoading, state: 'loaded'},
          messages: [],
          messagesLoading: {state: 'loaded', error: null},
          currentReferences: [],
        }
      } else {
        return {
          ...state,
          threads: new Map(state.threads),
        }
      }

    case 'DELETE_THREAD_ERROR':
      sendEvent('copilot.delete_thread_error', {...stringifyThread(action.thread), error: action.error})
      return {
        ...state,
        threadsLoading: {...state.threadsLoading, error: action.error},
        threads: new Map(state.threads.set(action.thread.id, action.thread)),
      }
    case 'DELETE_ALL_THREADS_ERROR': {
      for (const thread of action.threads) {
        sendEvent('copilot.delete_thread_error', {...stringifyThread(thread), error: action.error})
      }
      const updatedThreads = new Map(state.threads)
      for (const thread of action.threads) {
        updatedThreads.set(thread.id, thread)
      }
      return {
        ...state,
        threadsLoading: {...state.threadsLoading, error: action.error},
        threads: updatedThreads,
      }
    }
    case 'MESSAGE_ADDED': {
      sendEvent('copilot.message_added', {
        ...stringifyMessage(action.message),
        count: state.messages.length + 1,
        repoHasCustomInstructions: Boolean(action.repoHasCustomInstructions),
        usedRepoCustomInstructions: Boolean(action.usedRepoCustomInstructions),
      })

      let messages = [...state.messages, action.message]
      if (copilotFeatureFlags.immersiveSubthreading) {
        messages = addMessageToHierarchy(state.messages, action.message)
      }

      return {
        ...state,
        messages,
        // clear existing error so new messages can show
        messagesLoading: {state: 'loaded', error: null},
        threadHasNewMessages: true,
      }
    }
    case 'MESSAGE_FEEDBACK': {
      const messages = state.messages.map(m => ({...m}))
      const message = messages.find(m => m.id === action.message.id)
      if (message == null) {
        // this shouldn't happen, so log if it does
        sendEvent('copilot.message_feedback_no_message_found', {
          ...stringifyMessage(action.message),
        })
        return state
      }

      message.feedback = action.feedback

      return {
        ...state,
        messages,
      }
    }
    case 'MESSAGES_SET_SELECTED_MESSAGE': {
      const messages = selectActiveMessage(state.messages, action.message)

      return {
        ...state,
        messages,
        threadHasNewMessages: false,
      }
    }
    case 'MESSAGES_UNSELECT_PREVIOUS_MESSAGE': {
      const messages = unselectPreviousChild(state.messages, action.message)

      return {
        ...state,
        messages,
        threadHasNewMessages: false,
      }
    }
    case 'THREAD_UPDATED':
      return {
        ...state,
        threads: new Map(state.threads.set(action.thread.id, action.thread)),
        customCopilotId:
          state.selectedThreadID === action.thread.id ? action.thread.customCopilotID : state.customCopilotId,
      }
    case 'REFERENCES_LOADED':
      sendEvent('copilot.references_loaded', {count: action.references.length})
      return {
        ...state,
        currentReferences: state.currentReferences
          // remove potential duplicates
          .filter(oldRef => action.references.every(newRef => referenceID(newRef) !== referenceID(oldRef)))
          .concat(action.references),
      }
    case 'ADD_REFERENCE': {
      const newCurrentReferences = [
        ...state.currentReferences.filter(reference => !referencesAreEqual(reference, action.reference)),
        action.reference,
      ]
      if (newCurrentReferences.length > state.currentReferences.length) {
        sendEvent('copilot.add_reference', {
          ...stringifyReference(action.reference),
          source: action.source,
          count: state.currentReferences.length + 1,
        })
      }
      return {
        ...state,
        ...setCurrentReferences(newCurrentReferences),
      }
    }
    case 'REMOVE_REFERENCES': {
      const removedReferences = action.references
      if (removedReferences.length > 0) {
        sendEvent('copilot.remove_reference', {
          count: state.currentReferences.length - removedReferences.length,
        })
      }
      return {
        ...setCurrentReferences(state.currentReferences.filter(r => !removedReferences.includes(r))),
        action: 'REMOVE_REFERENCES',
      }
    }
    case 'SHOW_TOPIC_PICKER':
      return {
        ...state,
        showTopicPicker: action.show,
      }
    case 'CURRENT_TOPIC_UPDATED':
      if (action.topic) {
        sendEvent('copilot.current_topic_updated', {
          type: !action.topic ? 'none' : isDocset(action.topic) ? 'docset' : 'repository',
          mode: state.mode,
        })
      }
      return {
        ...state,
        currentTopic: action.topic,
        topicLoading: {...state.topicLoading, state: action.state},
      }
    case 'MESSAGE_STREAMING_STARTED':
      return {
        ...state,
        isWaitingOnCopilot: true,
        streamingMessage: action.message,
        messages: [...state.messages],
      }
    case 'MESSAGE_STREAMING_TOKEN_ADDED':
      return {
        ...state,
        streamingMessage: state.streamingMessage
          ? {...state.streamingMessage, content: state.streamingMessage.content + action.token}
          : null,
      }
    case 'MESSAGE_STREAMING_FUNCTION_CALLED':
      if (state.streamingMessage) {
        const prevExecutions = state.streamingMessage.skillExecutions || []
        const firstStartedIdx = prevExecutions.findIndex(fc => fc.status === 'started')
        const firstStartedExecution = firstStartedIdx >= 0 ? prevExecutions[firstStartedIdx] : null

        // Default to the previous executions if somehow we don't hit our expected conditions in the switch statement
        let executions = prevExecutions

        switch (action.status) {
          // If status is started, append to skillExecutions
          case 'started':
            executions = [
              ...prevExecutions,
              {
                slug: action.name,
                status: action.status,
                arguments: action.arguments,
                errorMessage: action.errorMessage,
                references: [],
              },
            ]
            break
          case 'completed':
            // Mark the first matching started execution as completed, and update its references.
            if (firstStartedExecution) {
              executions[firstStartedIdx] = {
                ...firstStartedExecution,
                status: action.status,
                references: action.references,
              }
            }
            break
          case 'error':
            // Mark the first matching started execution as errored.
            if (firstStartedExecution) {
              executions[firstStartedIdx] = {
                ...firstStartedExecution,
                status: action.status,
                errorMessage: action.errorMessage,
              }
            }
            break
        }

        return {
          ...state,
          streamingMessage: {
            ...state.streamingMessage,
            skillExecutions: executions,
          },
        }
      }
      return state
    case 'CLIENT_SKILL_CONFIRMATION_REQUEST': {
      return {
        ...state,
        clientSkillConfirmation: action.confirmation,
      }
    }
    case 'CLIENT_SKILLS_REQUEST': {
      return {
        ...state,
        streamingMessage: state.streamingMessage
          ? {
              ...state.streamingMessage,
              clientSkillsRequests: action.toolCalls,
            }
          : null,
      }
    }
    case 'READ_DOM_SKILL_INVOKED': {
      return {
        ...state,
        elementMap: action.elementMap,
      }
    }
    case 'MESSAGE_STREAMING_COMPLETED': {
      let defaultRecipient = state.defaultRecipient
      let newMessage: CopilotChatMessage | undefined
      let messages = state.messages

      if (state.streamingMessage) {
        newMessage = {
          ...state.streamingMessage,
          id: action.messageResponse.id,
          references: action.messageResponse.references,
          createdAt: action.messageResponse.createdAt,
          intent: action.messageResponse.intent,
          copilotAnnotations: action.messageResponse.copilotAnnotations,
          parentMessageID: action.messageResponse.parentMessageID,
          model: action.messageResponse.model,
          clientSide: false, // streamingMessage sets it to true, but we now got answer from server
        }
        defaultRecipient = getDefaultRecipient(newMessage, state)
        sendEvent('copilot.message_streaming_completed', {
          ...stringifyMessage(newMessage),
          ...stringifyTiming(action.timings),
          model: state.model?.id,
          mode: state.mode,
          count: state.messages.length + 1,
        })

        if (copilotFeatureFlags.immersiveSubthreading) {
          const messagesClone = messages.map(m => ({...m}))
          // Find last user message that user sent and set its ID to the parent message ID we got from response.
          // We need this because server is not returning the user message information back, just the response message.
          // But the response message should be having the correct parent message id that we can use here.

          // TODO: this likely should be updated to handle subthreads being changed by user while response is being streamed back
          // so that we would find the correct user message. Probably easiest is to find a user message with a missing ID - we should only have one.
          // Is it possible to switch subthreads while response is being streamed? We do seem to cancel and nullify state.streamingMessage
          // on failures and stops (see below) - we should do same with subthreads.

          // Note that before this change, user messages are storing fake client-side generated IDs (built by buildMessage method) until thread is reloaded.

          const parentMessage = messagesClone.find(m => m.id === newMessage?.parentMessageID)
          if (parentMessage == null) {
            const activeMessages = getActiveMessages(messagesClone)
            const lastActiveMessage = activeMessages[activeMessages.length - 1]
            if (lastActiveMessage !== undefined) {
              if (lastActiveMessage.clientSide && lastActiveMessage.role === 'user') {
                // If it's user message they submitted, change its ID to the one generated by server
                lastActiveMessage.id = newMessage.parentMessageID!
                // Mark message as available on server, so it can be used to chain future messages to
                // This code will need to stay even if above line is no longer neccesary due to relying on client-side IDs
                // ref https://github.com/github/copilot-productivity/issues/3613
                lastActiveMessage.clientSide = false
              } else {
                // If previous message is client-only non-user (assistant) message, chain to that
                newMessage.parentMessageID = lastActiveMessage.id
              }
            }
          }

          messages = addMessageToHierarchy(messagesClone, newMessage)
        } else {
          messages = [...state.messages, newMessage]
        }
      }
      return {
        ...state,
        defaultRecipient,
        isWaitingOnCopilot: false,
        streamingMessage: null,
        messages,
      }
    }
    case 'MESSAGE_STREAMING_FAILED':
      sendEvent('copilot.message_streaming_failed', {
        ...(state.streamingMessage ? stringifyMessage(state.streamingMessage) : {}),
        ...stringifyTiming(action.timings),
        model: state.model?.id,
        mode: state.mode,
      })
      return {
        ...state,
        isWaitingOnCopilot: false,
        streamingMessage: null,
      }
    case 'MESSAGE_STREAMING_STOPPED': {
      let newMessage: CopilotChatMessage | undefined
      // Attach incomplete messages to the last thread
      // Note that to continue this subthread from that point, we will reload thread from server to get correct server state
      const parentMessageID = getActiveMessages(state.messages).findLast(m => m.role === 'user')?.id

      if (state.streamingMessage) {
        // response already started streaming, just mark it as interrupted and insert it into the list
        newMessage = {
          ...state.streamingMessage,
          interrupted: true,
          parentMessageID,
        }
        sendEvent('copilot.message_streaming_stopped', {
          ...stringifyMessage(newMessage),
          ...stringifyTiming(action.timings),
          model: state.model?.id,
          mode: state.mode,
          count: state.messages.length + 1,
        })
      } else if (state.isWaitingOnCopilot) {
        // response hasn't started streaming yet, so just insert a dummy interrupted message
        newMessage = {
          id: crypto.randomUUID(),
          role: 'assistant',
          threadID: state.selectedThreadID ?? '',
          references: [],
          createdAt: new Date().toISOString(),
          interrupted: true,
          clientSide: true,
          parentMessageID,
        }
      }

      let messages = state.messages
      if (newMessage != null) {
        if (copilotFeatureFlags.immersiveSubthreading) {
          // While streaming, the user message isn't yet saved, even though it's part of `state.messages`. This means
          // that the streaming copilot message is linked to the last AI message, not its ephemeral user message.
          // Set the newMessage's parentMessageID to the user message, rather than the previous copilot response.
          const lastUserMessage = messages.findLast(m => m.role === 'user')
          if (lastUserMessage !== undefined) {
            newMessage.parentMessageID = lastUserMessage.id
          }

          messages = addMessageToHierarchy(messages, newMessage)
        } else {
          messages = [...state.messages, newMessage]
        }
      }
      return {
        ...state,
        isWaitingOnCopilot: false,
        streamingMessage: null,
        messages,
      }
    }
    case 'MESSAGES_CLEAR_LAST_ERROR': {
      if (copilotFeatureFlags.immersiveSubthreading) {
        const activeMessages = getActiveMessages(state.messages)
        const allMessages = state.messages
        const lastMessage = activeMessages[activeMessages.length - 1]
        const lastMessageHasError = lastMessage?.error || lastMessage?.interrupted
        let filteredMessages = allMessages
        if (lastMessageHasError) {
          filteredMessages = allMessages.filter(message => message.id !== lastMessage?.id)
        }
        return {
          ...state,
          streamingMessage: null,
          messages: [...filteredMessages],
        }
      } else {
        const lastMessage = state.messages[state.messages.length - 1]
        const lastMessageHasError = lastMessage?.error || lastMessage?.interrupted
        const newMessages = lastMessageHasError ? state.messages.slice(0, -1) : state.messages
        return {
          ...state,
          streamingMessage: null,
          messages: newMessages,
        }
      }
    }
    case 'SELECT_REFERENCE':
      if (action.reference) {
        sendEvent('copilot.select_reference', stringifyReference(action.reference))
      }
      return {
        ...state,
        selectedReference: action.reference,
      }
    case 'MODELS_LOADING':
      return {
        ...state,
        modelsLoading: {
          state: 'loaded',
          error: null,
        },
      }
    case 'MODELS_LOADING_ERROR':
      return {
        ...state,
        modelsLoading: {
          state: 'error',
          error: action.error,
        },
      }
    case 'MODELS_LOADED':
      return {
        ...state,
        model: (action.models || []).find(m => m.id === state.model.id) || state.model,
        availableModels: action.models,
      }
    case 'SELECT_MODEL': {
      // We can have image references set that aren't supported by newly selected models.
      // This will drop them.
      if (!action.model?.capabilities?.supports?.vision) {
        const currentReferences = state.currentReferences.filter(reference => reference.type !== 'image')
        state = setCurrentReferences(currentReferences)
      }

      if (state.mode !== 'immersive') return state

      sendEvent('copilot.select_model', {model: action.model?.name, mode: state.mode})
      return {
        ...state,
        model: action.model,
      }
    }
    case 'VIEW_ALL_THREADS':
      return {
        ...state,
        currentView: 'list',
      }
    case 'VIEW_CURRENT_THREAD':
      return {
        ...state,
        currentView: 'thread',
      }
    case 'IMPLICIT_CONTEXT_UPDATED':
      if (!referenceArraysAreEqual(action.context, state.context)) {
        return {
          ...state,
          context: action.context,
        }
      }
      return state
    case 'SET_TOP_REPOSITORIES':
      return {
        ...state,
        topRepositoriesCache: action.topics,
      }
    case 'SET_AGENTS':
      return {
        ...state,
        agents: action.agents,
      }

    case 'SET_CUSTOM_COPILOT': {
      return {
        ...state,
        customCopilots: state.customCopilots?.map(copilot => {
          if (copilot.id === action.customCopilot.id) {
            return action.customCopilot
          }
          return copilot
        }) ?? [action.customCopilot],
      }
    }
    case 'SET_CUSTOM_COPILOTS':
      return {
        ...state,
        customCopilots: action.customCopilots,
      }
    case 'SET_CUSTOM_COPILOT_ID':
      return {
        ...state,
        customCopilots: state.customCopilots,
        customCopilotId: action.customCopilotId,
      }
    case 'DELETE_COPILOT_SPACE':
      sendEvent('copilot.copilot_space_deleted', {
        ...stringifyCustomCopilot(action.copilot),
        count: (state.customCopilots?.length ?? 0) - 1,
        mode: state.mode,
      })
      {
        const newCustomCopilots = state.customCopilots?.filter(copilot => copilot.id !== action.copilot.id)
        if (state.customCopilotId === action.copilot.id) {
          return {
            ...state,
            ...setSelectedCopilotSpace(null),
            customCopilots: newCustomCopilots,
            messages: [],
            currentReferences: [],
          }
        } else {
          return {
            ...state,
            customCopilots: newCustomCopilots,
          }
        }
      }
    case 'DELETE_COPILOT_SPACE_ERROR':
      sendEvent('copilot.delete_copilot_space_error', {
        ...stringifyCustomCopilot(action.copilot),
        error: action.error,
      })
      return {
        ...state,
        customCopilots: state.customCopilots,
      }
    case 'MESSAGE_STREAMING_CONFIRMATION': {
      const confirmation = {
        title: action.title,
        message: action.message,
        confirmation: action.confirmation,
      }
      return {
        ...state,
        streamingMessage: state.streamingMessage
          ? {
              ...state.streamingMessage,
              confirmations: state.streamingMessage.confirmations
                ? [...state.streamingMessage.confirmations, confirmation]
                : [confirmation],
            }
          : null,
      }
    }
    case 'AGENT_ERROR': {
      const streamingMessage = state.streamingMessage
      const agentError = action.error

      return {
        ...state,
        streamingMessage: streamingMessage && {
          ...streamingMessage,
          agentErrors: [
            ...(streamingMessage.agentErrors ?? []),
            {
              type: agentError.type,
              code: agentError.code,
              message: agentError.message,
              identifier: agentError.identifier,
            },
          ],
        },
      }
    }
    case 'ENTITLEMENT_UPDATED':
      return {
        ...state,
        entitlement: action.entitlement ?? state.entitlement,
      }
    case 'TOGGLE_REPO_CUSTOM_INSTRUCTIONS':
      sendEvent('copilot.repo_custom_instructions_toggled', {
        isEnabling: Boolean(action.value),
      })
      return {
        ...state,
        repoCustomInstructionsEnabled: action.value,
      }
    case 'DISMISS_EDITOR_UPSELL_BANNER':
      return {
        ...state,
        isEditorUpsellBannerDismissed: true,
      }
    case 'DISMISS_AMBIENT_ERROR':
      return {
        ...state,
        ambientError: null,
      }
    case 'ADD_AMBIENT_ERROR': {
      return {
        ...state,
        ambientError: {message: action.message},
      }
    }
    case 'SET_PERSONAL_INSTRUCTIONS':
      return {
        ...state,
        personalInstructions: action.personalInstructions,
      }
    case 'SELECT_PLUGIN':
      return {
        ...state,
        activePlugin: action.plugin ?? undefined,
      }
    case 'SHARED_THREAD_UPDATED':
      sendEvent('copilot.shared_thread_update', stringifyThread(action.thread))
      return {
        ...state,
        threads: new Map(state.threads.set(action.thread.id, action.thread)),
      }
    case 'IMAGE_UPLOADED': {
      return {
        ...state,
        currentReferences: state.currentReferences.map(reference => {
          if (reference.type === 'image' && reference.id === action.referenceId) {
            return {
              ...reference,
              imageUrl: action.dotcomAttachment.previewUrl,
            }
          }
          return reference
        }),
      }
    }
  }
}

/**
 * Stringifies the given message while cleaning sensitive information from it.
 */
function stringifyMessage(message: CopilotChatMessage) {
  if (!message) {
    return stringifyObjectValues({})
  }
  const obj: Record<string, unknown> = {
    id: message.id,
    role: message.role,
    createdAt: message.createdAt,
    threadID: message.threadID,
    referenceCount: message.references?.length ?? 0,
  }
  if (message.intent) {
    obj.intent = message.intent
  }
  if (message.error) {
    obj.error = message.error
  }
  if (message.copilotAnnotations) {
    obj.copilotAnnotations = cleanCopilotAnnotations(message.copilotAnnotations)
  }
  if (message.skillExecutions) {
    obj.skillExecutions = cleanSkillExecutions(message.skillExecutions)
  }
  if (message.interrupted) {
    obj.interrupted = true
  }
  return stringifyObjectValues(obj)
}

/**
 * Stringifies the given thread while cleaning sensitive information from it.
 */
function stringifyThread(thread: CopilotChatThread) {
  if (!thread) {
    return stringifyObjectValues({})
  }
  return stringifyObjectValues({
    id: thread.id,
    createdAt: thread.createdAt,
    updatedAt: thread.updatedAt,
    currentReferenceCount: thread.currentReferences?.length ?? 0,
  })
}

function stringifyCustomCopilot(copilot: CustomCopilot) {
  if (!copilot) {
    return stringifyObjectValues({})
  }

  return stringifyObjectValues({
    id: copilot.id,
  })
}

/**
 * Stringifies the given reference while cleaning sensitive information from it.
 */
function stringifyReference(reference: CopilotChatReference) {
  if (!reference) {
    return stringifyObjectValues({})
  }
  return stringifyObjectValues({
    type: reference.type,
  })
}

/**
 * Remove sensitive information from skillExecutions in preparation for logging.
 */
function cleanSkillExecutions(skillExecutions: SkillExecution[] | undefined) {
  if (!skillExecutions) {
    return []
  }
  return skillExecutions.map(execution => ({
    slug: execution?.slug,
    status: execution?.status,
    argumentCount: execution?.arguments?.length ?? 0,
    errorMessage: execution?.errorMessage,
    references: execution?.references?.length ?? 0,
  }))
}

/**
 * Remove sensitive information from copilotAnnotations in preparation for logging.
 */
function cleanCopilotAnnotations(annotations: CopilotAnnotations | undefined) {
  if (!annotations) {
    return undefined
  }
  return {
    CodeVulnerability: annotations.CodeVulnerability?.map(vuln => ({
      details: {
        type: vuln?.details?.type,
      },
    })),
    PublicCodeReference: annotations.PublicCodeReference?.map(ref => ({
      details: {
        license: ref?.details?.license,
        language: ref?.details?.language,
      },
    })),
  }
}

/**
 * Converts the timings into relative times for reporting.
 */
function stringifyTiming(timings: Timings) {
  const result: Record<string, number> = {
    totalTime: timings.endTime - timings.startTime,
  }
  if (timings.firstByte !== undefined) result['ttfb'] = timings.firstByte - timings.startTime
  if (timings.firstToken !== undefined) result['ttft'] = timings.firstToken - timings.startTime
  return result
}

function getDefaultRecipient(message: CopilotChatMessage, state: CopilotChatState): string | undefined {
  const author = findAuthor(message, state.currentUserLogin)
  if (author.type === 'agent') {
    return author.name
  }
}
