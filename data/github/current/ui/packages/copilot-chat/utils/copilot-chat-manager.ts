import {copilotChatHeaderButtonID, reviewUserMessage} from '@github-ui/copilot-chat/utils/constants'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import {verifiedFetch} from '@github-ui/verified-fetch'

import type {
  AddCopilotChatReferenceEvent,
  OpenCopilotChatEvent,
  SearchCopilotEvent,
  SymbolChangedEvent,
} from './copilot-chat-events'
import {
  buildMessage,
  ERROR_MSG,
  ERRORS,
  getThreadStaticSuggestions,
  isDocset,
  isRepository,
  isThreadOlderThan4Hours,
  makeRepositoryReference,
  referencesAreEqual,
} from './copilot-chat-helpers'
import {CopilotChatMessageStreamer} from './copilot-chat-message-streamer'
import type {CopilotChatAction, CopilotChatState} from './copilot-chat-reducer'
import {CopilotChatService} from './copilot-chat-service'
import type {
  AppAgentRequestErrorPayload,
  ChatError,
  CopilotChatAgent,
  CopilotChatEventPayload,
  CopilotChatIntentsType,
  CopilotChatMessage,
  CopilotChatModel,
  CopilotChatOrg,
  CopilotChatReference,
  CopilotChatRepo,
  CopilotChatSettings,
  CopilotChatSuggestions,
  CopilotChatThread,
  CopilotClientConfirmation,
  CopilotModel,
  Docset,
  MessageStreamingErrorType,
  MessageStreamingResponse,
  MessageStreamingResponseError,
  NotAuthorizedForAgentErrorPayload,
  RepositoryReference,
  TopicItem,
} from './copilot-chat-types'
import {CopilotChatIntents, MESSAGE_STREAMING_ERROR_TYPES, SUPPORTED_FUNCTIONS} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'
import {copilotLocalStorage} from './copilot-local-storage'
import {toCopilotChatModels} from './models'

export const LOAD_LATEST_THREAD_FF = 'copilot_load_latest_thread'
export const STAFF_PROMPT_DIALOG_FF = 'copilot_staff_prompt_dialog'

export type Dispatcher = (value: CopilotChatAction) => void
const multipleAgentsAttemptMessage =
  "Only one agent is allowed per thread, and their context can't be shared. If you want to interact with another agent, please start a new thread and @ mention the new agent."

// We do not expect the list of models to change during a browser session, so cache the response
let modelsCache: CopilotChatModel[] | null = null

export class CopilotChatManager {
  dispatch: Dispatcher
  service: CopilotChatService
  private unstickyReferencesFeatureEnabled = copilotFeatureFlags.unstickyReferences
  private getChatState: () => CopilotChatState
  private hasCEorCBAccess?: boolean

  constructor(
    dispatch: Dispatcher,
    apiURL: string,
    ssoOrganizations: CopilotChatOrg[],
    getChatState: () => CopilotChatState,
    realIp?: string,
    hasCEorCBAccess?: boolean,
  ) {
    this.dispatch = dispatch
    this.service = new CopilotChatService(apiURL, ssoOrganizations, realIp)
    this.getChatState = getChatState
    this.hasCEorCBAccess = hasCEorCBAccess
  }

  /**
   * Opens a new chat window
   * @param thread the thread to display (leave null to try to find an appropriate thread to open or start a new thread)
   * @param currentView
   * @param source what is triggering the open, e.g. 'search-bar' or 'header'
   * @param expectedReference a reference the thread should be relevant to, if the default one doesn't reference this, create a new thread.
   * @returns
   */
  async openChat(
    thread: CopilotChatThread | null,
    currentView: 'thread' | 'list',
    source: string,
    chatVisibleSettingPath?: string,
    expectedReference?: CopilotChatReference,
  ) {
    this.dispatch({type: 'OPEN_COPILOT_CHAT', source})

    if (currentView === 'thread') {
      await this.findOrStartNewThread(thread, expectedReference)
    }

    copilotLocalStorage.setCollapsedState(false)
    setCopilotButtonAriaExpanded(true)

    if (chatVisibleSettingPath) {
      const data = new FormData()
      data.set('copilot_chat_visible', 'true')
      void verifiedFetch(chatVisibleSettingPath, {method: 'PUT', body: data})
    }
  }

  closeChat() {
    this.dispatch({type: 'CLOSE_COPILOT_CHAT'})
    copilotLocalStorage.setCollapsedState(true)
    setCopilotButtonAriaExpanded(false)
  }

  hideChat(chatVisibleSettingPath?: string) {
    this.dispatch({type: 'HIDE_COPILOT_CHAT'})
    this.closeChat()

    if (chatVisibleSettingPath) {
      const data = new FormData()
      data.set('copilot_chat_visible', 'false')
      void verifiedFetch(chatVisibleSettingPath, {method: 'PUT', body: data})
    }
  }

  toggleRepoCustomInstructions(value: boolean) {
    this.dispatch({type: 'TOGGLE_REPO_CUSTOM_INSTRUCTIONS', value})
    copilotLocalStorage.setRepoCustomInstructionsState(value)
  }

  viewAllThreads() {
    this.dispatch({type: 'VIEW_ALL_THREADS'})
  }

  viewCurrentThread() {
    this.dispatch({type: 'VIEW_CURRENT_THREAD'})
  }

  async sendChatMessage(
    thread: CopilotChatThread | null,
    content: string,
    references: CopilotChatReference[],
    topic?: CopilotChatRepo | Docset,
    context?: CopilotChatReference[],
    confirmations?: CopilotClientConfirmation,
    customInstructions?: string,
    model?: CopilotChatModel | null,
  ) {
    const topicIsDocset = isDocset(topic)
    const repo = topicIsDocset ? undefined : topic

    if (topicIsDocset && !references.some(ref => ref.type === 'docset' && ref.name === topic.name)) {
      references.push({
        type: 'docset',
        name: topic.name,
        id: topic.id,
        avatarUrl: topic.avatarUrl,
        repos: topic.repos,
        description: topic.description,
      })
    }

    return this.sendMessage(
      thread,
      content,
      CopilotChatIntents.conversation,
      references,
      repo,
      context,
      confirmations,
      customInstructions,
      model,
    )
  }

  async stopStreaming() {
    const {streamer} = this.getChatState()
    if (streamer) {
      await streamer.stop()
      this.dispatch({type: 'MESSAGE_STREAMING_STOPPED'})
    }
  }

  private async sendMessage(
    thread: CopilotChatThread | null,
    content: string,
    intent: CopilotChatIntentsType,
    references: CopilotChatReference[],
    repo?: CopilotChatRepo,
    context?: CopilotChatReference[],
    confirmations?: CopilotClientConfirmation,
    customInstructions?: string,
    model?: CopilotChatModel | null,
  ) {
    const confirmationsArray = confirmations ? [confirmations] : []
    const userMessage = buildMessage({role: 'user', content, references, thread, confirmations: confirmationsArray})

    this.dispatch({type: 'MESSAGE_ADDED', message: userMessage})

    const newMessage = buildMessage({role: 'assistant', content: '', thread})

    this.dispatch({type: 'WAITING_ON_COPILOT', loading: true})

    // create thread if one is not given
    if (!thread) {
      const res = await this.service.createThread()
      if (res.ok) {
        thread = res.payload
        copilotLocalStorage.migrateNullThreadToNewThread(thread.id)
        this.dispatch({type: 'THREAD_CREATED', thread})
      } else {
        this.handleSendMessageError(thread, makeBasicError(res.error))
        return
      }
    }

    this.dispatch({type: 'THREAD_UPDATED', thread: {...thread, updatedAt: new Date().toISOString()}})

    // as of https://github.com/github/copilot-core-productivity/issues/1040 we need to leave
    // the reference in the thread if we're talking about a knowledge base (Docset)
    if (this.unstickyReferencesFeatureEnabled) {
      this.dispatch({type: 'CLEAR_REFERENCES', threadID: thread.id})
    }

    const implicitContext =
      !references.length || (references.length === 1 && references[0]?.type === 'repository') ? context : undefined
    sendEvent('copilot.implicit_context', {
      usedImplicitContext: !!implicitContext,
      type: implicitContext?.[0]?.type,
      count: implicitContext?.length,
    })
    if (!references.length && repo) references = [makeRepositoryReference(repo)]

    const customInstructionsArray: string[] = []

    // repo-level custom instructions
    const repoInstructionsEnabled = copilotLocalStorage.getRepoCustomInstructionsState()
    if (repo?.customInstructions && repoInstructionsEnabled) customInstructionsArray.push(repo.customInstructions)
    // org-level custom instructions
    if (customInstructions) customInstructionsArray.push(customInstructions)

    // When we send a message to a thread using a particular model, save that model for the thread.
    if (model) {
      copilotLocalStorage.setModel(thread.id, model)
    }

    const {mode} = this.getChatState()

    const res = await this.service.createMessageStreaming(
      thread.id,
      content,
      intent,
      mode,
      references,
      implicitContext ?? [],
      confirmationsArray,
      customInstructionsArray,
      model?.id,
    )
    if (!res.ok) {
      this.handleSendMessageError(thread, makeBasicError(res.error))
      return
    }

    const reader = res.response.body?.getReader()
    if (!reader) {
      this.handleSendMessageError(thread, makeBasicError(ERROR_MSG))
      return
    }

    const streamer = new CopilotChatMessageStreamer(reader)

    this.dispatch({type: 'MESSAGE_STREAMING_STARTED', message: newMessage, streamer})

    await this.handleStreamingMessage(thread, streamer, implicitContext)
  }

  addReference(reference: CopilotChatReference, source: string) {
    this.dispatch({type: 'ADD_REFERENCE', reference, source})
  }

  removeReference(referenceIndex: number) {
    this.dispatch({type: 'REMOVE_REFERENCES', referenceIndexes: [referenceIndex]})
  }

  removeReferences(referenceIndexes: number[]) {
    this.dispatch({type: 'REMOVE_REFERENCES', referenceIndexes})
  }

  clearCurrentReferences = () => {
    this.dispatch({type: 'CLEAR_CURRENT_REFERENCES'})
  }

  selectModel(model: CopilotChatModel) {
    this.dispatch({type: 'SELECT_MODEL', model})
    copilotLocalStorage.setModel(this.getChatState().selectedThreadID, model)
  }

  setCopilotSettings(settings: CopilotChatSettings) {
    copilotLocalStorage.settings = settings
  }

  async dismissAttachKnowledgeBaseHerePopover() {
    this.dispatch({type: 'DISMISS_ATTACH_KNOWLEDGE_BASE_HERE_POPOVER'})
    await verifiedFetch('/settings/dismiss-notice/copilot_for_docs_attach_knowledge_base_here', {
      method: 'POST',
    })
  }

  async dismissKnowledgeBaseAttachedToChatPopover() {
    this.dispatch({type: 'DISMISS_KNOWLEDGE_BASE_ATTACHED_TO_CHAT_POPOVER'})
    await verifiedFetch('/settings/dismiss-notice/copilot_for_docs_knowledge_base_attached_to_chat', {
      method: 'POST',
    })
  }

  async selectThread(thread: CopilotChatThread | null, options?: {clearTopic?: boolean; includeThreads?: boolean}) {
    const {clearTopic, includeThreads = true} = options ?? {}

    await this.fetchModels() // Make sure we have these first so that we can ensure the model we apply is available

    await this.stopStreaming()

    this.dispatch({type: 'SELECT_THREAD', thread, clearTopic})
    const thingsToFetch: Array<Promise<unknown>> = []

    thingsToFetch.push(this.fetchMessages(thread?.id || null))
    if (includeThreads) thingsToFetch.push(this.fetchThreads())

    await Promise.all(thingsToFetch)
  }

  addMessage(
    role: 'user' | 'assistant',
    thread: CopilotChatThread | null,
    content: string,
    references: CopilotChatReference[],
  ) {
    const message = buildMessage({role, content, references, thread})
    this.dispatch({type: 'MESSAGE_ADDED', message})
  }

  async renameThread(thread: CopilotChatThread, newName: string) {
    const res = await this.service.renameThread(thread.id, newName)
    if (res.ok) {
      this.dispatch({type: 'THREAD_UPDATED', thread: {...thread, name: newName}})
    }
  }

  async clearThread(thread: CopilotChatThread) {
    const res = await this.service.clearThread(thread.id)
    if (res.ok) {
      this.dispatch({type: 'CLEAR_THREAD', threadID: thread.id})
    }
  }

  async deleteThreadKeepSelection(thread: CopilotChatThread) {
    this.dispatch({type: 'DELETE_THREAD_KEEP_SELECTION', thread})
    const res = await this.service.deleteThread(thread.id)
    if (!res.ok) this.dispatch({type: 'DELETE_THREAD_ERROR', thread, error: res.error})
  }

  async deleteThread(thread: CopilotChatThread) {
    this.dispatch({type: 'DELETE_THREAD', thread})
    const res = await this.service.deleteThread(thread.id)
    if (!res.ok) this.dispatch({type: 'DELETE_THREAD_ERROR', thread, error: res.error})
  }

  async generateSuggestions(context: CopilotChatReference | CopilotChatRepo | Docset, threadID?: string | null) {
    let suggestions: CopilotChatSuggestions | null = null
    if (threadID) {
      const res = await this.service.generateSuggestions(context, threadID)
      if (res.ok) suggestions = res.payload
    } else {
      const type = 'type' in context && typeof context.type === 'string' ? context.type : 'repository'
      suggestions = getThreadStaticSuggestions(type)
    }

    this.dispatch({type: 'SUGGESTIONS_GENERATED', suggestions})
  }

  clearSuggestions(): void {
    this.dispatch({type: 'CLEAR_SUGGESTIONS'})
  }

  async handleOpenPanelEvent(
    thread: CopilotChatThread | null,
    e: OpenCopilotChatEvent,
    topic?: CopilotChatRepo | Docset,
  ) {
    const payload = e.payload
    // We always want to create a new thread for icebreakers, they don't make sense to include in an existing thread
    if (payloadIsIcebreaker(payload) || payloadIsNewThread(payload)) {
      await this.selectThread(null)
      thread = null
    } else if (payloadHasIntent(payload, [CopilotChatIntents.reviewPr])) {
      this.addMessage('user', payload.thread, reviewUserMessage, payload.references)
      this.addMessage('assistant', payload.thread, payload.completion, payload.references)
      if (isFeatureEnabled(LOAD_LATEST_THREAD_FF)) {
        // don't load all the threads as part of selecting the thread
        void this.selectThread(payload.thread, {includeThreads: false})
      } else {
        void this.selectThread(payload.thread, {includeThreads: true})
      }
    } else {
      thread = await this.findOrStartNewThread(thread)
    }

    this.dispatch({type: 'HANDLE_EVENT_START', references: payload.references, id: payload.id})

    // conversation events are only used to set up references, unless it is an icebreaker
    if (
      payloadHasIntent(payload, [
        CopilotChatIntents.conversation,
        CopilotChatIntents.discussFileDiff,
        CopilotChatIntents.reviewPr,
      ]) &&
      !payloadIsIcebreaker(payload)
    )
      return

    let source = `blob ${payload.intent}`
    if (payload.id) {
      source = `element ${e.payload.id}`
    }
    sendEvent('copilot.open_copilot_chat', {source})

    await this.sendMessage(
      thread,
      payload.content,
      payload.intent,
      payload.references ?? [],
      isRepository(topic) ? topic : undefined,
    )
  }

  async handleSearchCopilotEvent(e: SearchCopilotEvent) {
    const topic = await this.fetchCurrentRepo(e.repoNwo)
    const ref: RepositoryReference[] = topic ? [{type: 'repository', ...topic}] : []

    void this.openChat(null, 'thread', 'search-bar')
    await this.sendMessage(null, e.content, CopilotChatIntents.conversation, ref)
    sendEvent('copilot.open_copilot_chat', {source: 'search-bar'})
  }

  async handleAddReferenceEvent(e: AddCopilotChatReferenceEvent) {
    // make sure there's a thread to add the reference to
    await this.findOrStartNewThread()
    this.addReference(e.reference, 'event')
    if (e.openPanel) {
      this.dispatch({type: 'OPEN_COPILOT_CHAT', source: 'event', id: e.id})
    }
  }

  handleSymbolChangedEvent(e: SymbolChangedEvent) {
    const symbolContext = e.context
    this.dispatch({type: 'IMPLICIT_CONTEXT_UPDATED', context: [symbolContext]})
  }

  getSelectedThread(state: CopilotChatState): CopilotChatThread | null {
    if (!state.selectedThreadID) return null
    return state.threads.get(state.selectedThreadID) || null
  }

  sortThreads(threads: Map<string, CopilotChatThread>): CopilotChatThread[] {
    const threadsArr = Array.from(threads.values())
    return threadsArr.sort((a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime())
  }

  async sendMessageToNewThread(
    prevThreadID: string | null,
    message: string,
    refs: CopilotChatReference[],
    context?: CopilotChatReference[],
  ) {
    if (message.trim() === '') return

    if (prevThreadID) {
      copilotLocalStorage.setSavedMessageFast(prevThreadID, null)
      copilotLocalStorage.clearCurrentReferences(prevThreadID)
    }
    // Create a new thread and send the message
    await this.sendMessage(null, message, CopilotChatIntents.conversation, refs, undefined, context)
  }

  async fetchMessages(threadID: string | null) {
    const refs = copilotLocalStorage.getCurrentReferences(threadID)

    if (!threadID) {
      this.threadDataLoaded([], refs || [])
      return
    }

    this.dispatch({type: 'MESSAGES_UPDATED', state: 'loading'})

    const res = await this.service.listMessages(threadID)
    if (res.ok) {
      const thread = res.payload.thread
      this.threadDataLoaded(res.payload.messages, refs || thread.currentReferences || [])
    } else {
      this.dispatch({type: 'MESSAGES_UPDATED', state: 'error'})
    }
  }

  selectReference(reference: CopilotChatReference | null) {
    this.dispatch({type: 'SELECT_REFERENCE', reference})
  }

  setTopRepositoryTopics(topics: TopicItem[] | undefined) {
    this.dispatch({type: 'SET_TOP_REPOSITORIES', topics})
  }

  private async handleStreamingMessage(
    thread: CopilotChatThread,
    streamer: CopilotChatMessageStreamer,
    implicitContext?: CopilotChatReference[],
  ) {
    try {
      for await (const message of streamer.stream()) {
        await this.processStreamingMessage(thread, message, implicitContext)
      }
    } catch (e) {
      const error = this.isWrappedStreamingResponseError(e)
        ? this.getStreamingErrorMessage(e.error)
        : makeBasicError(ERROR_MSG)
      this.handleSendMessageError(thread, error)

      return
    }
  }

  private isWrappedStreamingResponseError(e: unknown): e is {error: MessageStreamingResponseError} {
    return (
      !!e &&
      typeof e === 'object' &&
      'error' in e &&
      !!e.error &&
      typeof e.error === 'object' &&
      'errorType' in e.error &&
      typeof e.error.errorType === 'string' &&
      MESSAGE_STREAMING_ERROR_TYPES.includes(e.error.errorType as MessageStreamingErrorType)
    )
  }

  private async processStreamingMessage(
    thread: CopilotChatThread,
    messageResponse: MessageStreamingResponse,
    implicitContext?: CopilotChatReference[],
  ) {
    switch (messageResponse.type) {
      case 'content': {
        this.dispatch({type: 'MESSAGE_STREAMING_TOKEN_ADDED', token: messageResponse.body})
        break
      }
      case 'functionCall': {
        if (functionIsSupported(messageResponse.name)) {
          this.dispatch({
            type: 'MESSAGE_STREAMING_FUNCTION_CALLED',
            name: messageResponse.name,
            status: messageResponse.status,
            arguments: messageResponse.arguments,
            errorMessage: messageResponse.errorMessage,
            references: messageResponse.references,
          })
        }
        break
      }
      case 'confirmation': {
        this.dispatch({
          type: 'MESSAGE_STREAMING_CONFIRMATION',
          title: messageResponse.title,
          message: messageResponse.message,
          confirmation: messageResponse.confirmation,
        })
        break
      }
      case 'complete': {
        this.dispatch({type: 'MESSAGE_STREAMING_COMPLETED', messageResponse})
        await this.handleSendMessageSuccess(thread)
        if (implicitContext && implicitContext.length > 0 && copilotFeatureFlags.followUpThreadSuggestions)
          await this.generateSuggestions(implicitContext[0]!, thread.id)
        break
      }
      case 'error': {
        const errMsg = this.getStreamingErrorMessage(messageResponse)
        this.handleSendMessageError(thread, errMsg)
        break
      }
      case 'debug': {
        // eslint-disable-next-line no-console
        console.log('Prompt Body:', messageResponse.body)
        break
      }
      case 'agentError':
        this.dispatch({
          type: 'AGENT_ERROR',
          error: {
            type: messageResponse.agentErrorType,
            code: messageResponse.code,
            message: messageResponse.message,
            identifier: messageResponse.identifier,
          },
        })
        break
    }
  }

  private getStreamingErrorMessage(res: MessageStreamingResponseError): ChatError {
    switch (res.errorType) {
      case 'publicCode': {
        let docsURL =
          'https://docs.github.com/en/copilot/managing-copilot/managing-copilot-as-an-individual-subscriber/managing-copilot-policies-as-an-individual-subscriber'
        let message = `This response cannot be shown because it references public code, which is restricted by [your Copilot settings](${docsURL}).`

        if (this.hasCEorCBAccess) {
          docsURL =
            'https://docs.github.com/en/enterprise-cloud@latest/copilot/managing-copilot/managing-github-copilot-in-your-organization/managing-policies-for-copilot-in-your-organization'
          message = `This response cannot be shown because it references public code, which is restricted by [your organization's Copilot settings](${docsURL}).`
        }

        return {
          type: 'basic',
          isError: true,
          message,
        }
      }
      case 'filtered':
        return makeBasicError(ERRORS[403] || ERROR_MSG)
      case 'contentTooLarge':
        return makeBasicError(ERRORS[413] || ERROR_MSG)
      case 'rateLimit':
        return makeBasicError(ERRORS[429] || ERROR_MSG)
      case 'agentUnauthorized': {
        const details = JSON.parse(res.description) as NotAuthorizedForAgentErrorPayload
        const authorizeURL = `You haven't authorized ${details.name} to access your account. You can do that by going here: ${window.location.origin}/login/oauth/authorize?client_id=${details.client_id}`
        return {type: 'agentUnauthorized', isError: true, message: authorizeURL, details}
      }
      case 'agentRequest': {
        const details = JSON.parse(res.description) as AppAgentRequestErrorPayload
        return {type: 'agentRequest', isError: true, message: details.message, details}
      }
      case 'multipleAgentsAttempt': {
        return makeBasicError(multipleAgentsAttemptMessage)
      }
      case 'networkError':
        return makeBasicError(ERRORS[408] || ERROR_MSG)
      case 'exception':
      default:
        return makeBasicError(ERROR_MSG)
    }
  }

  private async handleSendMessageSuccess(thread: CopilotChatThread) {
    copilotLocalStorage.setSavedMessageFast(thread.id, null)
    copilotLocalStorage.clearCurrentReferences(thread.id)

    this.dispatch({type: 'WAITING_ON_COPILOT', loading: false})

    thread = await this.generateThreadName(thread)
    this.dispatch({type: 'THREAD_UPDATED', thread: {...thread, updatedAt: new Date().toISOString()}})
  }

  private handleSendMessageError(thread: CopilotChatThread | null, error: ChatError) {
    const message = buildMessage({role: 'assistant', content: '', error, thread})
    this.dispatch({type: 'MESSAGE_ADDED', message})
    this.dispatch({type: 'WAITING_ON_COPILOT', loading: false})
    this.dispatch({type: 'MESSAGE_STREAMING_FAILED'})
  }

  async fetchModels() {
    if (modelsCache) return

    this.dispatch({type: 'MODELS_LOADING'})

    const res = await this.service.listModels()

    if (res.ok) {
      const models = toCopilotChatModels(res.payload)
      modelsCache = models
      this.dispatch({type: 'MODELS_LOADED', models})

      const storedModelID = copilotLocalStorage.getModel(this.getChatState().selectedThreadID)?.id
      const model = models.find(m => m.id === storedModelID)
      if (model) {
        this.dispatch({type: 'SELECT_MODEL', model})
      }
    } else {
      this.dispatch({type: 'MODELS_LOADING_ERROR', error: res.error})
    }
  }

  async acceptModelPolicy(model: CopilotModel) {
    if (!model.policy) return
    if (model.policy.state === 'enabled') return

    await this.service.setModelPolicyState(model.id, 'enabled')
    modelsCache = null
    void this.fetchModels()
  }

  async fetchThreads(): Promise<CopilotChatThread[] | null> {
    this.dispatch({type: 'THREADS_LOADING'})

    const res = await this.service.fetchThreads()
    if (!res.ok) {
      // There is a bit of a race condition with the THREADS_LOADING event
      // Wait 10ms before dispatching the THREADS_LOADING_ERROR event
      setTimeout(() => this.dispatch({type: 'THREADS_LOADING_ERROR', message: res.error}), 100)
      return null
    }

    // There is a bit of a race condition with the THREADS_LOADING event
    // Wait 10ms before dispatching the THREADS_LOADED event
    setTimeout(() => this.dispatch({type: 'THREADS_LOADED', threads: res.payload}), 100)

    return res.payload
  }

  async fetchLatestThread(threadId?: string): Promise<CopilotChatThread | null> {
    const res = await this.service.fetchLatestThread(threadId)
    if (!res.ok) {
      return null
    }

    if (res.payload) {
      this.dispatch({type: 'LATEST_THREAD_LOADED', latestThread: res.payload})
    }
    return res.payload
  }

  /**
   * Finds a thread to show to the user in a new chat, or starts a new thread if none are found.
   * @param currentThread The current thread to show to the user.
   * @param expectedReference A reference the thread should be relevant to, if the default one doesn't reference this, create a new thread.
   */
  private async findOrStartNewThread(
    currentThread?: CopilotChatThread | null,
    expectedReference?: CopilotChatReference,
  ): Promise<CopilotChatThread | null> {
    let thread: CopilotChatThread | null = null

    if (currentThread) {
      thread = currentThread
    } else {
      if (isFeatureEnabled(LOAD_LATEST_THREAD_FF)) {
        const previouslySelectedThreadID = copilotLocalStorage.selectedThreadID || undefined
        thread = await this.fetchLatestThread(previouslySelectedThreadID)
      } else {
        const threads = await this.fetchThreads()
        if (threads?.length) {
          const previouslySelectedThreadID = copilotLocalStorage.selectedThreadID
          thread = (previouslySelectedThreadID && threads.find(t => t.id === previouslySelectedThreadID)) || threads[0]!
        }
      }
    }

    if (thread && isThreadOlderThan4Hours(thread)) thread = null

    if (thread && expectedReference) {
      const response = await this.service.listMessages(thread.id)
      if (response.ok) {
        const messages = response.payload.messages
        const len = messages?.length
        // Check for the last user message (len - 2) in the thread and see if any of its references match the the expected reference
        if (len >= 2 && !messages[len - 2]?.references?.find(ref => referencesAreEqual(ref, expectedReference))) {
          thread = null
        }
      }
    }

    await this.selectThread(thread, {includeThreads: false})

    return thread
  }

  private async generateThreadName(thread: CopilotChatThread): Promise<CopilotChatThread> {
    if (thread.name) return thread

    const res = await this.service.generateThreadName(thread.id)
    if (res.ok) thread = {...thread, name: res.payload}

    return thread
  }

  public async fetchAgents(agentsPath: string): Promise<CopilotChatAgent[]> {
    const res = await this.service.listAgents(agentsPath)
    let agents: CopilotChatAgent[] = []
    if (res.ok) {
      agents = res.payload
      this.dispatch({type: 'SET_AGENTS', agents})
    }

    return agents
  }

  public async fetchCurrentRepo(repoID: number | string): Promise<CopilotChatRepo | undefined> {
    this.dispatch({type: 'CURRENT_TOPIC_UPDATED', topic: undefined, state: 'loading'})
    const res = await this.service.fetchRepo(repoID)
    if (res.ok) {
      this.dispatch({type: 'CURRENT_TOPIC_UPDATED', topic: res.payload, state: 'loaded'})
      return res.payload
    } else {
      this.dispatch({type: 'CURRENT_TOPIC_UPDATED', topic: undefined, state: 'error'})
    }
    return undefined
  }

  public async fetchKnowledgeBases() {
    this.dispatch({type: 'KNOWLEDGE_BASES_LOADING'})
    const res = await this.service.listDocsets()
    if (res.ok) {
      this.dispatch({type: 'KNOWLEDGE_BASES_LOADED', knowledgeBases: res.payload})
    } else {
      this.dispatch({type: 'KNOWLEDGE_BASES_LOADING_ERROR', message: res.error})
    }
    return res
  }

  public async fetchImplicitContext(url: string, owner: string, repo: string) {
    const res = await this.service.fetchImplicitContext(url, owner, repo)
    if (res.ok) {
      const context = !res.payload ? undefined : Array.isArray(res.payload) ? res.payload : [res.payload]
      this.dispatch({type: 'IMPLICIT_CONTEXT_UPDATED', context})
    } else {
      return undefined
    }
  }

  public async deleteDocset(docset: Docset) {
    const res = await this.service.deleteDocset(docset)
    return res.ok
  }

  public clearCurrentTopic = () => {
    this.dispatch({type: 'CURRENT_TOPIC_UPDATED', topic: undefined, state: 'loaded'})
  }

  public showTopicPicker = (value = true) => {
    this.dispatch({type: 'SHOW_TOPIC_PICKER', show: value})
  }

  private threadDataLoaded(messages: CopilotChatMessage[], references: CopilotChatReference[]) {
    this.dispatch({
      type: 'MESSAGES_UPDATED',
      messages,
      state: 'loaded',
    })

    this.dispatch({
      type: 'REFERENCES_LOADED',
      references,
    })
  }
}

function payloadIsNewThread(payload: CopilotChatEventPayload) {
  return payloadHasIntent(payload, [CopilotChatIntents.conversation]) && 'newThread' in payload && payload.newThread
}

function payloadIsIcebreaker(payload: CopilotChatEventPayload) {
  return (
    payloadHasIntent(payload, [CopilotChatIntents.explain, CopilotChatIntents.suggest]) ||
    (payloadHasIntent(payload, [CopilotChatIntents.conversation]) && payloadHasContent(payload))
  )
}

function payloadHasContent(payload: CopilotChatEventPayload): payload is CopilotChatEventPayload & {content: string} {
  return 'content' in payload && typeof payload.content == 'string'
}

function payloadHasIntent<const Intent extends CopilotChatIntentsType>(
  payload: CopilotChatEventPayload,
  intents: readonly Intent[],
): payload is Extract<typeof payload, {intent: Intent}> {
  const set = new Set<string>(intents)
  return set.has(payload.intent)
}

function functionIsSupported(name: string): boolean {
  return SUPPORTED_FUNCTIONS.includes(name) || (copilotFeatureFlags.issueCreation && name === 'githubissuecreate')
}

function makeBasicError(message: string): ChatError {
  return {isError: true, message, type: 'basic'}
}

function setCopilotButtonAriaExpanded(ariaExpanded?: boolean) {
  const copilotButton = document.getElementById(copilotChatHeaderButtonID)
  // If it is currently collapsed, we are expanding the chat
  copilotButton?.setAttribute('aria-expanded', ariaExpanded ? 'true' : 'false')
}
