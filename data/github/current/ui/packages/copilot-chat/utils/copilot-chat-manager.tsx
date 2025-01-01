// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {sendEvent} from '@github-ui/hydro-analytics'
import {clearSessionStorageByKeyPrefix} from '@github-ui/use-safe-storage/session-storage'
import {verifiedFetch} from '@github-ui/verified-fetch'

import type {ImmersivePlugin} from '../plugin/copilot-immersive-plugin'
import {copilotChatHeaderButtonID, reviewUserMessage} from './constants'
import type {
  AddCopilotChatReferenceEvent,
  OpenCopilotChatEvent,
  SearchCopilotEvent,
  SymbolChangedEvent,
} from './copilot-chat-events'
import {
  buildMessage,
  ERROR_MSG,
  ERRORS_BY_STATUS,
  ERRORS_BY_TYPE,
  getCustomInstructionsFromReferences,
  getThreadStaticSuggestions,
  hasCustomInstructions,
  isDocset,
  isFileReference,
  isRepository,
  isThreadOlderThan4Hours,
  makeOrgInstructionsReference,
  makeRepositoryReference,
  referencesAreEqual,
} from './copilot-chat-helpers'
import {CopilotChatMessageStreamer} from './copilot-chat-message-streamer'
import type {CopilotChatState, Dispatcher, Timings} from './copilot-chat-reducer'
import {CopilotChatService} from './copilot-chat-service'
import {getActiveMessages, getParentMessage} from './copilot-chat-subthreading-helpers'
import type {
  AppAgentRequestErrorPayload,
  ChatError,
  ClientSideSkillDefinition,
  CopilotAgentConfirmation,
  CopilotChatAgent,
  CopilotChatDuplicate,
  CopilotChatEventPayload,
  CopilotChatIntentsType,
  CopilotChatMessage,
  CopilotChatMessageFeedback,
  CopilotChatMode,
  CopilotChatModel,
  CopilotChatOrg,
  CopilotChatReference,
  CopilotChatReferenceType,
  CopilotChatRepo,
  CopilotChatSettings,
  CopilotChatThread,
  CopilotClientConfirmation,
  CopilotCustomInstructions,
  CopilotModel,
  CustomCopilotId,
  CustomCopilotPayload,
  Docset,
  FileReference,
  MediaContentItem,
  MessageStreamingErrorType,
  MessageStreamingResponse,
  MessageStreamingResponseError,
  NotAuthorizedForAgentErrorPayload,
  RepositoryReference,
  SkillOptions,
  ToolCallResult,
  TopicItem,
} from './copilot-chat-types'
import {CopilotChatIntents, MESSAGE_STREAMING_ERROR_TYPES, SUPPORTED_FUNCTIONS} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'
import {copilotLocalStorage} from './copilot-local-storage'
import {customCopilotIdFromThread} from './custom-copilots-helpers'
import {filterOutCustomCopilotReferences} from './custom-copilots-references-helpers'
import {getSelectedThread} from './get-selected-thread'
import {toCopilotChatModels} from './models'
import {registerSkillsForPath} from './register-skills-for-path'
import {SkillExecutor} from './skills/skill-executor'
import {type DotcomFileAttachment, UploadableFileAttachment} from './uploadable-file-attachment'

export const MAX_MESSAGES_PER_THREAD = 3000
export const MAX_SUBTHREADS_PER_MESSAGE = 99

const multipleAgentsAttemptMessage =
  "Only one agent is allowed per thread, and their context can't be shared. If you want to interact with another agent, please start a new thread and @ mention the new agent."

// We do not expect the list of models to change during a browser session, so cache the response
let modelsCache: CopilotChatModel[] | null = null

export interface SelectThreadOptions {
  clearTopic?: boolean
  includeThreads?: boolean
}

export class CopilotChatManager {
  dispatch: Dispatcher
  service: CopilotChatService
  private getChatState: () => CopilotChatState
  private hasCEorCBAccess: boolean
  private timings: Omit<Timings, 'endTime'> = {startTime: 0}
  private skillExecutor?: SkillExecutor

  // The following variables are stateful and require stable chat manager instance to support streaming,
  // interrupting and reloading the thread after interrupt.
  private streamer?: CopilotChatMessageStreamer
  private messageAbortController?: AbortController
  private reloadingThreadPromise: Promise<boolean> | undefined
  private fetchingThreadID: string | null = null
  private afterThreadReloadCallback: ((messages: CopilotChatMessage[]) => void) | undefined
  private pendingThreadsByCustomCopilotId: Map<string, string | null> = new Map()

  private plugins: ImmersivePlugin[]

  constructor(
    dispatch: Dispatcher,
    apiURL: string,
    ssoOrganizations: CopilotChatOrg[],
    getChatState: () => CopilotChatState,
    realIp: string | undefined,
    chatService: CopilotChatService | undefined,
    hasCEorCBAccess: boolean | undefined,
    plugins: ImmersivePlugin[],
    apiVersion?: string,
  ) {
    this.dispatch = dispatch
    this.service = chatService ?? new CopilotChatService(apiURL, ssoOrganizations, realIp, apiVersion)
    this.getChatState = getChatState
    this.hasCEorCBAccess = !!hasCEorCBAccess
    this.plugins = plugins
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

    const state = this.getChatState()
    const entryPointId = state.entryPointId ?? copilotChatHeaderButtonID
    setCopilotButtonAriaExpanded(entryPointId, true)

    if (chatVisibleSettingPath) {
      const data = new FormData()
      data.set('copilot_chat_visible', 'true')
      void verifiedFetch(chatVisibleSettingPath, {method: 'PUT', body: data})
    }
  }

  closeChat() {
    this.dispatch({type: 'CLOSE_COPILOT_CHAT'})
    copilotLocalStorage.setCollapsedState(true)
    const state = this.getChatState()
    const entryPointId = state.entryPointId ?? copilotChatHeaderButtonID
    setCopilotButtonAriaExpanded(entryPointId, false)
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

  maxMessagesReached() {
    return this.getChatState().messages.length >= MAX_MESSAGES_PER_THREAD
  }

  async sendChatMessage({
    thread,
    content,
    references,
    topic,
    context,
    confirmations,
    customInstructions,
    model,
    customCopilotId,
    intent = CopilotChatIntents.conversation,
    tools,
    clientToolResults,
    parentMessageId,
    modeOverride,
    skillOptions,
  }: {
    thread: CopilotChatThread | null
    content: string
    references: CopilotChatReference[]
    topic?: CopilotChatRepo | Docset
    context?: CopilotChatReference[]
    confirmations?: CopilotClientConfirmation
    customInstructions?: CopilotCustomInstructions
    model?: CopilotChatModel | null
    customCopilotId?: CustomCopilotId | null
    intent?: CopilotChatIntentsType
    tools?: ClientSideSkillDefinition[]
    clientToolResults?: ToolCallResult[]
    parentMessageId?: string
    modeOverride?: string
    skillOptions?: SkillOptions
  }) {
    const topicIsDocset = isDocset(topic)
    const repo = topicIsDocset ? undefined : topic
    let threadToUse = thread

    // If no thread is selected, but there is a pending thread and the
    // submitted message is coming from a custom copilot / space, use the pending thread.
    const pendingThreadId = this.getPendingThreadId(customCopilotId)
    if (!threadToUse && customCopilotId && pendingThreadId) {
      threadToUse = this.getThreadById(pendingThreadId)
      this.removePendingThreadId(customCopilotId)
    }

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

    const mediaContent: MediaContentItem[] = copilotFeatureFlags.attachImagesImmersive
      ? await Promise.all(
          references
            .filter(x => x.type === 'image')
            .map(x => x.attachment)
            .map(async (attachment: DotcomFileAttachment): Promise<MediaContentItem> => {
              const url = await attachment.url()
              const file = attachment.file
              return {
                mediaType: file.type,
                name: file.name,
                url,
                chatAttachmentUrl: url,
                width: attachment.width,
                height: attachment.height,
              }
            }),
        )
      : []

    // We filter the images out of references
    // as we don't want to send images to CAPI in the references array.
    // We'll send it in a separate media field instead.
    let filteredReferences: CopilotChatReference[] = references.filter(ref => ref.type !== 'image')
    // don't include unauthenticated figma references
    filteredReferences = filteredReferences.filter(ref => ref.type !== 'figma' || !ref.authenticationRequired)

    // Remove edited references from storage on message submission.
    if (threadToUse != null) {
      this.clearEditedReferencesFromSessionStorage(threadToUse.id)
    }

    return this.sendNewMessage(
      threadToUse,
      content,
      mediaContent,
      intent,
      filteredReferences,
      repo,
      context,
      confirmations,
      customInstructions,
      model,
      customCopilotId,
      tools,
      clientToolResults,
      parentMessageId,
      modeOverride,
      skillOptions,
    )
  }

  public FindLastMessageID(): string {
    const activeMessages = getActiveMessages(this.getChatState().messages)
    return activeMessages[activeMessages.length - 1]?.id || 'root'
  }

  async retryLastUnsuccessfulChatMessage(thread: CopilotChatThread) {
    const {currentTopic, context, customInstructions, model} = this.getChatState()
    const topicIsDocset = isDocset(currentTopic)
    const repo = topicIsDocset ? undefined : currentTopic

    const lastUserMessage = getActiveMessages(this.getChatState().messages).findLast(m => m.role === 'user')

    if (!lastUserMessage?.content) return
    const references = thread.currentReferences || []
    const mediaContent = lastUserMessage.mediaContent || []

    this.dispatch({type: 'MESSAGES_CLEAR_LAST_ERROR'})
    this.unselectPreviousChildMessage(lastUserMessage)

    let parentMessageID = ''
    if (lastUserMessage.clientSide) {
      // If the last message is client-side-only, find last known server-side message and chain to that
      // If it's a user message, that means we have siblings and had error using retry feature
      // If it's an assistant message, that means we should continue the subthread
      // If there is no last active message, then this is the first message and should point to the root.
      const activeMessages = getActiveMessages(this.getChatState().messages)
      const lastServerMessage = activeMessages.findLast(message => !message.clientSide)
      if (lastServerMessage) {
        if (lastServerMessage.role === 'user') {
          // If last server message is user message, create new sibling to it
          // Note that we will keep previous messages/errors in UI until full page reload
          parentMessageID = lastServerMessage.parentMessageID || 'root'
        } else {
          // If last server message is assistant message, chain to it
          parentMessageID = lastServerMessage.id
        }
      } else {
        parentMessageID = 'root'
      }
    } else {
      parentMessageID = lastUserMessage.id
    }

    return this.sendMessage(
      thread,
      lastUserMessage.content,
      mediaContent,
      references,
      CopilotChatIntents.conversation,
      context,
      repo,
      customInstructions,
      model,
      undefined,
      parentMessageID,
    )
  }

  /** Resends the user message that is a parent of an assistant message and creates a subthread
   * This supports the retry button in the assistant messages */
  async retryUserChatMessage(thread: CopilotChatThread, message: CopilotChatMessage, selectedModel?: CopilotChatModel) {
    const {currentTopic, context, customInstructions, model} = this.getChatState()
    const topicIsDocset = isDocset(currentTopic)
    const repo = topicIsDocset ? undefined : currentTopic

    let parentMessage: CopilotChatMessage | undefined = undefined

    if (message.parentMessageID) {
      // Find the parent message by matching its ID with the parentMessageID of the provided message
      parentMessage = this.getChatState().messages.findLast(m => m.id === message.parentMessageID)
    }

    if (!parentMessage || !parentMessage.content) return

    // Terminate active message list after the parent so we can show streaming message
    this.unselectPreviousChildMessage(parentMessage)

    const references = parentMessage.references || []
    const mediaContent = parentMessage.mediaContent || []

    // Send same content as before, but include additional parent message ID
    // This prevents the user message from getting stored as a new message.
    return this.sendMessage(
      thread,
      parentMessage.content,
      mediaContent,
      references,
      CopilotChatIntents.conversation,
      context,
      repo,
      customInstructions,
      selectedModel || model,
      undefined,
      parentMessage.id,
    )
  }

  /** Edits the user message and creates a subthread */
  async editUserChatMessage(thread: CopilotChatThread, message: CopilotChatMessage, content: string) {
    if (!content) return // Don't send empty messages

    const {currentTopic, context, customInstructions, messages, model} = this.getChatState()
    const topicIsDocset = isDocset(currentTopic)
    const repo = topicIsDocset ? undefined : currentTopic

    const parentMessage = getParentMessage(messages, message)
    if (!parentMessage) return

    const parentMessageID = parentMessage?.id || ''

    const confirmationResponses = message.clientConfirmations ?? []
    const references = message.references || []
    const mediaContent = message.mediaContent || []

    const userMessage = buildMessage({
      role: 'user',
      content,
      mediaContent,
      references,
      thread,
      confirmationResponses,
      parentMessageID,
    })

    const hasInstructions = hasCustomInstructions(repo, references)

    this.dispatch({
      type: 'MESSAGE_ADDED',
      message: userMessage,
      repoHasCustomInstructions: Boolean(hasInstructions),
      usedRepoCustomInstructions: Boolean(hasInstructions && this.repoInstructionsEnabled()),
    })

    if (this.reloadingThreadPromise) {
      this.dispatch({type: 'WAITING_ON_COPILOT', loading: true})

      // After thread is reloaded, re-add the new user message so it shows up in the UI
      this.afterThreadReloadCallback = () => {
        this.dispatch({
          type: 'MESSAGE_ADDED',
          message: userMessage,
          repoHasCustomInstructions: Boolean(hasInstructions),
          usedRepoCustomInstructions: Boolean(hasInstructions && this.repoInstructionsEnabled()),
        })
      }

      // Wait until thread reloads successfully
      // If reload failed, discard new message
      if (!(await this.reloadingThreadPromise)) return
    }

    // Find the first ancestor that is stored on server, and attach to that
    // This handles scenario where there are multiple errors and/or edit attempts between last server reply and the message being edited
    let ancestor: CopilotChatMessage | undefined = parentMessage
    while (ancestor) {
      if (!ancestor.clientSide) {
        break
      }
      ancestor = getParentMessage(messages, ancestor)
    }

    // Send same content as before, but include additional parent message ID
    return this.sendMessage(
      thread,
      content,
      mediaContent,
      references,
      CopilotChatIntents.conversation,
      context,
      repo,
      customInstructions,
      model,
      undefined,
      ancestor?.id || '',
    )
  }

  handleFeedback(message: CopilotChatMessage, feedback: CopilotChatMessageFeedback) {
    this.dispatch({type: 'MESSAGE_FEEDBACK', message, feedback})
  }

  setSelectedMessage(message: CopilotChatMessage) {
    this.dispatch({type: 'MESSAGES_SET_SELECTED_MESSAGE', message})
  }

  unselectPreviousChildMessage(message: CopilotChatMessage) {
    this.dispatch({type: 'MESSAGES_UNSELECT_PREVIOUS_MESSAGE', message})
  }

  async stopStreaming() {
    if (this.streamer) {
      // there is an active stream that we can just abort
      await this.streamer.stop()
      this.streamer = undefined
    } else {
      // currently waiting for Copilot to begin streaming, so just cancel the initial request
      this.messageAbortController?.abort()
    }

    this.dispatch({type: 'MESSAGE_STREAMING_STOPPED', timings: this.completeTiming()})
  }

  async getSystemPrompt() {
    const {mode} = this.getChatState()

    const prompt = await this.systemPrompt(mode)
    return prompt
  }

  // Used to create a thread. Usage of this should be limited to not create too many empty threads.
  async createThread(
    customCopilotId?: CustomCopilotId | null,
    preventThreadSelection = false,
  ): Promise<CopilotChatThread> {
    const res = await this.service.createThread(customCopilotId)
    let thread: CopilotChatThread
    if (res.ok) {
      thread = res.payload
      copilotLocalStorage.migrateNullThreadToNewThread(thread.id)
      this.dispatch({type: 'THREAD_CREATED', thread, preventThreadSelection})

      return thread
    } else {
      throw new Error(res.error)
    }
  }

  private async sendNewMessage(
    thread: CopilotChatThread | null,
    content: string,
    mediaContent: MediaContentItem[],
    intent: CopilotChatIntentsType,
    references: CopilotChatReference[],
    repo?: CopilotChatRepo,
    context?: CopilotChatReference[],
    confirmations?: CopilotClientConfirmation,
    customInstructions?: CopilotCustomInstructions,
    model?: CopilotChatModel | null,
    customCopilotId?: CustomCopilotId | null,
    tools?: ClientSideSkillDefinition[],
    clientToolResults?: ToolCallResult[],
    parentMessageID?: string,
    modeOverride?: string,
    skillOptions?: SkillOptions,
  ) {
    const {clientSkillConfirmation} = this.getChatState()
    if (clientSkillConfirmation) {
      // Copilot was waiting for a confirmation repsonse, but the user sent a message instead.
      // Clear out the pending confirmation and any pending clientside skills.
      this.dispatch({type: 'CLIENT_SKILL_CONFIRMATION_REQUEST', confirmation: undefined})
      this.skillExecutor?.resetExecution()
    }
    const confirmationsArray = confirmations ? [confirmations] : []
    const userMessage = buildMessage({
      role: 'user',
      content,
      mediaContent,
      references,
      thread,
      confirmationResponses: confirmationsArray,
      parentMessageID: parentMessageID || this.FindLastMessageID(), // User messages are chained to the last visible message
      clientToolResults,
      skillOptions,
    })

    const hasInstructions = hasCustomInstructions(repo, references)
    this.dispatch({
      type: 'MESSAGE_ADDED',
      message: userMessage,
      repoHasCustomInstructions: Boolean(hasInstructions),
      usedRepoCustomInstructions: Boolean(hasInstructions && this.repoInstructionsEnabled()),
    })

    // create thread if one is not given
    if (!thread) {
      try {
        thread = await this.createThread(customCopilotId)
      } catch (e) {
        // This shouldn't happen, since the error coming out of createThread should be an Error object.
        let errorMessage = 'An unexpected error has occurred.'
        if (e instanceof Error) {
          errorMessage = e.message
        }
        this.handleSendMessageError(thread, makeBasicError(errorMessage), content)
        return
      }
    }

    this.dispatch({type: 'THREAD_UPDATED', thread: {id: thread.id, updatedAt: new Date().toISOString()}})

    // as of https://github.com/github/copilot-core-productivity/issues/1040 we need to leave
    // the reference in the thread if we're talking about a knowledge base (Docset)
    this.dispatch({type: 'CLEAR_CURRENT_REFERENCES', keepTypes: ['docset', 'magic-knowledge-base']})

    // When we send a message to a thread using a particular model, save that model for the thread.
    if (model) {
      copilotLocalStorage.setModel(thread.id, model)
    }

    let overrideParentMessageID = ''
    if (!parentMessageID) {
      const activeMessages = getActiveMessages(this.getChatState().messages)
      const lastMessage = activeMessages[activeMessages.length - 1]
      if (lastMessage) {
        if (lastMessage.clientSide) {
          // If the last message is client-side-only, find last known server-side message and chain to that
          // Note that we are looking for assistant messages, so this will start new subthread at the last successful user message
          // If there is no last active message, then this is the first message and should point to the root.
          parentMessageID =
            activeMessages.findLast(message => !message.clientSide && message.role === 'assistant')?.id || 'root'
        } else {
          parentMessageID = lastMessage.id
        }
      } else {
        parentMessageID = 'root'
      }

      if (this.reloadingThreadPromise) {
        // Set loading state, since we have to wait
        this.dispatch({type: 'WAITING_ON_COPILOT', loading: true})
        this.afterThreadReloadCallback = messages => {
          if (messages.length === 0) return
          // We need to find the parent message ID of the last message in the current subthread
          // This should be the last message in the messages array, as we just cancelled it before reloading from server
          overrideParentMessageID = messages[messages.length - 1]!.id
          userMessage.parentMessageID = overrideParentMessageID
          this.dispatch({
            type: 'MESSAGE_ADDED',
            message: userMessage,
            repoHasCustomInstructions: Boolean(hasInstructions),
            usedRepoCustomInstructions: Boolean(hasInstructions && this.repoInstructionsEnabled()),
          })
        }

        // If reload failed, discard new message
        if (!(await this.reloadingThreadPromise)) return
      }
    }

    return this.sendMessage(
      thread,
      content,
      mediaContent,
      references,
      intent,
      context,
      repo,
      customInstructions,
      model,
      confirmations,
      overrideParentMessageID || parentMessageID,
      tools,
      clientToolResults,
      modeOverride,
      skillOptions,
    )
  }

  private async sendMessage(
    thread: CopilotChatThread,
    content: string,
    mediaContent: MediaContentItem[],
    references: CopilotChatReference[],
    intent: CopilotChatIntentsType,
    context?: CopilotChatReference[],
    repo?: CopilotChatRepo,
    customInstructions?: CopilotCustomInstructions,
    model?: CopilotChatModel | null,
    confirmations?: CopilotClientConfirmation,
    parentMessageID?: string,
    tools: ClientSideSkillDefinition[] = [],
    clientToolResults?: ToolCallResult[],
    modeOverride?: string,
    skillOptions?: SkillOptions,
  ) {
    const confirmationsArray = confirmations ? [confirmations] : []
    const streamingMessage = buildMessage({role: 'assistant', content: '', mediaContent: [], thread, parentMessageID})
    streamingMessage.messageIndex = -1

    this.dispatch({type: 'WAITING_ON_COPILOT', loading: true})

    const implicitContext =
      !references.length || (references.length === 1 && references[0]?.type === 'repository') ? context : undefined
    sendEvent('copilot.implicit_context', {
      usedImplicitContext: !!implicitContext,
      type: implicitContext?.[0]?.type,
      count: implicitContext?.length,
    })
    if (!references.length && repo) references = [makeRepositoryReference(repo)]

    const messageCustomInstructions: CopilotCustomInstructions[] = []

    // repo-level custom instructions
    // pull custom instructions from references instead
    if (this.repoInstructionsEnabled()) {
      if (copilotFeatureFlags.topicsAsReferences) {
        const instructionsFromReferences = getCustomInstructionsFromReferences(references)
        messageCustomInstructions.push(...instructionsFromReferences)
      } else if (repo?.customInstructions) {
        messageCustomInstructions.push(...repo.customInstructions)
      }
    }

    // NOTE: this has not been shipped yet and it might not ever be
    // org-level custom instructions
    // Only add default custom instructions if one is not associated with the repo
    if (
      customInstructions?.type === 'Organization' &&
      !messageCustomInstructions.find(i => i.type === 'Organization')
    ) {
      messageCustomInstructions.push(customInstructions)
    }

    if (customInstructions?.type === 'Assistant') {
      messageCustomInstructions.push(customInstructions)
    }

    // render reference if custom instructions exists
    const orgInstructions = messageCustomInstructions.find(i => i.type === 'Organization')
    if (orgInstructions) {
      references.push(makeOrgInstructionsReference(orgInstructions.owner))
    }

    const customInstructionsArray: string[] = messageCustomInstructions.map(i => i.prompt)

    const {mode} = this.getChatState()

    this.timings = {startTime: Date.now()}
    this.streamer = undefined
    this.messageAbortController = new AbortController()

    // Register tools that should be available on the current path
    const clientTools = [...tools, ...registerSkillsForPath(window.location.pathname)]

    try {
      const defaultOptions = {
        threadID: thread.id,
        messageID: streamingMessage.id,
        content,
        mediaContent,
        intent,
        mode: modeOverride || mode,
        references,
        context: implicitContext ?? [],
        confirmations: confirmationsArray,
        customInstructions: customInstructionsArray,
        model: model?.id,
        customCopilotID: customCopilotIdFromThread(thread),
        parentMessageID,
        tools: clientTools,
        clientToolResults,
        signal: this.messageAbortController.signal,
        skillOptions,
      }

      const options = this.activePlugin?.overrideCreateMessageOptions
        ? await this.activePlugin.overrideCreateMessageOptions(defaultOptions)
        : defaultOptions
      const res = await this.service.createMessageStreaming(options)
      if (!res.ok) {
        if (this.messageAbortController.signal.aborted) return
        this.handleSendMessageError(thread, makeBasicError(res.error), content)
      } else {
        const reader = res.response.body?.getReader()
        if (!reader) {
          this.handleSendMessageError(thread, makeBasicError(ERROR_MSG), content)
          return
        }
        // Extract the request ID for easy error reporting later
        // Note: This does not exist on local env since glb is not running to add the header
        streamingMessage.requestID = res.response.headers.get('x-github-request-id') || undefined
        const streamer = new CopilotChatMessageStreamer(reader)
        this.streamer = streamer

        this.dispatch({type: 'MESSAGE_STREAMING_STARTED', message: streamingMessage})

        await this.handleStreamingMessage(thread, streamer)
      }
    } finally {
      this.streamer = undefined
      this.messageAbortController = undefined
    }
  }

  private repoInstructionsEnabled() {
    return (
      (copilotFeatureFlags.repoCustomInstructions || copilotFeatureFlags.repoCustomInstructionsPreview) &&
      copilotLocalStorage.getRepoCustomInstructionsState()
    )
  }

  private async populateReferenceLanguage(reference: FileReference) {
    const response = await this.service.fetchLanguageForFileReference(reference)
    if (response.ok && response.payload.language) {
      const {languageName, languageId} = response.payload.language
      this.replaceReference(reference, {...reference, languageName, languageId})
    }
  }

  clearEditedReferencesFromSessionStorage(threadID: string) {
    if (copilotFeatureFlags.copilotPersistEditedDraftIssues) {
      // Clear session storage for edited references
      clearSessionStorageByKeyPrefix(`edited-${threadID}-`)
    }
  }

  addReference(reference: CopilotChatReference, source: string) {
    this.dispatch({type: 'ADD_REFERENCE', reference, source})

    if (isFileReference(reference) && (reference.languageId === undefined || reference.languageName === undefined)) {
      void this.populateReferenceLanguage(reference)
    }
  }

  removeReference(reference: CopilotChatReference | undefined) {
    if (reference) {
      abortInProcessImageDownloads([reference])
      this.dispatch({type: 'REMOVE_REFERENCES', references: [reference]})
    }
  }

  removeReferences(references: CopilotChatReference[]) {
    abortInProcessImageDownloads(references)
    this.dispatch({type: 'REMOVE_REFERENCES', references})
  }

  clearCurrentReferences = (keepTypes?: CopilotChatReferenceType[]) => {
    if (!keepTypes || !keepTypes.includes('image')) {
      abortInProcessImageDownloads(this.getChatState().currentReferences)
    }
    this.dispatch({type: 'CLEAR_CURRENT_REFERENCES', keepTypes})
  }

  /**
   * Replace the given reference in `currentReferences`. The reference to delete will be matched based on ID, and if
   * it is not found the operation will be a no-op.
   */
  replaceReference(referenceToDelete: CopilotChatReference, referenceToInsert: CopilotChatReference) {
    this.dispatch({type: 'REPLACE_REFERENCE', referenceToDelete, referenceToInsert})
  }

  setImageAttachmentUploaded(referenceId: string, dotcomAttachment: DotcomFileAttachment) {
    this.dispatch({type: 'IMAGE_UPLOADED', referenceId, dotcomAttachment})
  }

  selectModel(model: CopilotChatModel, updateLocalStorage = true) {
    this.dispatch({type: 'SELECT_MODEL', model})
    if (updateLocalStorage) {
      copilotLocalStorage.setModel(this.getChatState().selectedThreadID, model)
    }
  }

  selectPlugin(pluginID: string | null) {
    const activePluginID = this.getChatState().activePlugin ?? null
    if (activePluginID === pluginID) return

    // if pluginID is defined, ensure that the plugin actually exists
    if (pluginID) {
      const plugin = this.plugins.find(p => p.id === pluginID)
      if (!plugin) return
    }

    this.dispatch({type: 'SELECT_PLUGIN', plugin: pluginID})
  }

  private get activePlugin(): ImmersivePlugin | undefined {
    return this.plugins.find(p => p.id === this.getChatState().activePlugin)
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

  async selectThread(thread: CopilotChatThread | null, options?: SelectThreadOptions) {
    const {clearTopic, includeThreads = true} = options ?? {}

    await this.fetchModels() // Make sure we have these first so that we can ensure the model we apply is available

    await this.stopStreaming()

    this.dispatch({type: 'CLEAR_SHARED_THREAD_CHANNEL'})

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
    mediaContent: MediaContentItem[],
    references: CopilotChatReference[],
    clientConfirmations?: CopilotClientConfirmation[],
    clientSkillConfirmations?: CopilotAgentConfirmation[],
  ) {
    const message = buildMessage({
      role,
      content,
      mediaContent,
      references,
      thread,
      confirmationResponses: clientConfirmations,
      clientSkillConfirmations,
      parentMessageID: this.FindLastMessageID(), // Attach client skill request to any last message in current subthread
    })
    this.dispatch({type: 'MESSAGE_ADDED', message})
  }

  async renameThread(thread: CopilotChatThread, newName: string) {
    const res = await this.service.renameThread(thread.id, newName)
    if (res.ok) {
      this.dispatch({type: 'THREAD_UPDATED', thread: {id: thread.id, name: newName}})
    }
  }

  dismissAmbientError() {
    this.dispatch({type: 'DISMISS_AMBIENT_ERROR'})
  }

  addAmbientError(message: string) {
    this.dispatch({type: 'ADD_AMBIENT_ERROR', message})
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

  async deleteAllThreadKeepSelection(threads: CopilotChatThread[]) {
    this.dispatch({type: 'DELETE_ALL_THREADS_KEEP_SELECTION', threads})
    const threadIds = threads.map(thread => thread.id)
    // Delete threads in batches of 100 as this is our current limit in API endpoint
    const batchSize = 100
    for (let i = 0; i < threadIds.length; i += batchSize) {
      const batch = threadIds.slice(i, i + batchSize)
      const res = await this.service.deleteAllThreads({threadIDs: batch})
      if (!res.ok) {
        this.dispatch({type: 'DELETE_ALL_THREADS_ERROR', threads, error: res.error})
      }
    }
  }

  async deleteThread(thread: CopilotChatThread) {
    // Clear edited references from session storage before deleting the thread
    this.clearEditedReferencesFromSessionStorage(thread.id)
    this.dispatch({type: 'DELETE_THREAD', thread})
    const res = await this.service.deleteThread(thread.id)
    if (!res.ok) this.dispatch({type: 'DELETE_THREAD_ERROR', thread, error: res.error})
  }

  generateSuggestions(context: CopilotChatReference | CopilotChatRepo | Docset) {
    const suggestions = getThreadStaticSuggestions(context)
    this.dispatch({type: 'SUGGESTIONS_GENERATED', suggestions})
  }

  clearSuggestions(): void {
    this.dispatch({type: 'CLEAR_SUGGESTIONS'})
  }

  async handleOpenPanelEvent(
    thread: CopilotChatThread | null,
    e: OpenCopilotChatEvent,
    chatIsOpen: boolean,
    topic?: CopilotChatRepo | Docset,
  ) {
    const payload = e.payload
    const newThreadIsOpen = !thread && chatIsOpen
    const activeThreadIsOpen = thread && chatIsOpen
    // We always want to create a new thread for icebreakers, they don't make sense to include in an existing thread
    if (payloadIsIcebreaker(payload) || payloadIsNewThread(payload)) {
      await this.selectThread(null)
      thread = null
    } else if (payloadHasIntent(payload, [CopilotChatIntents.reviewPr])) {
      this.addMessage('user', payload.thread, reviewUserMessage, [], payload.references)
      this.addMessage('assistant', payload.thread, payload.completion, [], payload.references)
      // don't load all the threads as part of selecting the thread
      void this.selectThread(payload.thread, {includeThreads: false})
    } else if (newThreadIsOpen) {
      // If chat is open and there's no thread, skip finding a previous thread
    } else {
      // If the chat is not open and we are not attaching to an existing thread, create a new thread.
      if (copilotFeatureFlags.copilotChatOpeningThreadSwitch) {
        if ((payloadIsAttachToThread(payload) && !chatIsOpen) || activeThreadIsOpen) {
          thread = await this.findOrStartNewThread(thread)
        } else {
          await this.selectThread(null)
          thread = null
        }
      } else {
        thread = await this.findOrStartNewThread(thread)
      }
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
    ) {
      return
    }

    let source = `blob ${payload.intent}`
    if (payload.id) {
      source = `element ${e.payload.id}`
    }
    sendEvent('copilot.open_copilot_chat', {source})

    await this.sendNewMessage(
      thread,
      payload.content,
      [],
      payload.intent,
      payload.references ?? [],
      isRepository(topic) ? topic : undefined,
      undefined,
      undefined,
      undefined,
      null,
      undefined,
    )
  }

  async handleSearchCopilotEvent(e: SearchCopilotEvent) {
    const topic = await this.fetchCurrentRepo(e.repoNwo)
    const ref: RepositoryReference[] = topic ? [{type: 'repository', ...topic}] : []

    void this.openChat(null, 'thread', 'search-bar')
    await this.sendNewMessage(null, e.content, [], CopilotChatIntents.conversation, ref)
    sendEvent('copilot.open_copilot_chat', {source: 'search-bar'})
  }

  handleAddReferenceEvent(e: AddCopilotChatReferenceEvent) {
    this.addReference(e.reference, 'event')
    if (e.openPanel) {
      this.dispatch({type: 'OPEN_COPILOT_CHAT', source: 'event', id: e.id})
    }
  }

  handleSymbolChangedEvent(e: SymbolChangedEvent) {
    const symbolContext = e.context
    this.dispatch({type: 'IMPLICIT_CONTEXT_UPDATED', context: [symbolContext]})
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
    if (message.trim() === '') {
      const [inferred, newMessage] = this.tryInferMessage(refs)
      if (!inferred || !newMessage) {
        return
      } else {
        message = newMessage
      }
    }

    if (prevThreadID) {
      copilotLocalStorage.setSavedMessageFast(prevThreadID, null)
      copilotLocalStorage.clearCurrentReferences(prevThreadID)
    }
    // Create a new thread and send the message
    await this.sendNewMessage(null, message, [], CopilotChatIntents.conversation, refs, undefined, context)
  }

  resolvePromise: (value: boolean | PromiseLike<boolean>) => void = () => {}

  // Create new promise that blocks new messages from being added until thread is reloaded
  public startThreadReload() {
    this.reloadingThreadPromise = new Promise(resolve => {
      this.resolvePromise = resolve
    })
  }

  // Destroy blocking promise created by startThreadReload
  public cancelThreadReload() {
    this.resolvePromise(false)
    this.resolvePromise = () => {}
    this.reloadingThreadPromise = undefined
    this.afterThreadReloadCallback = undefined
    this.fetchingThreadID = null
  }

  async fetchMessages(
    threadID: string | null,
    reloadThread: boolean = false,
    expectNewMessages: boolean = false,
  ): Promise<() => void> {
    const refs = copilotLocalStorage.getCurrentReferences(threadID)

    if (!threadID) {
      this.threadDataLoaded(threadID, [], refs || [])
      return () => {}
    }

    if (!reloadThread) {
      this.dispatch({type: 'MESSAGES_UPDATED', state: 'loading'})
    }

    const originalMessages = this.getChatState().messages
    this.fetchingThreadID = threadID

    const getMessages = async (shouldExpectNewMessages: boolean): Promise<boolean> => {
      const res = await this.service.listMessages(threadID)
      // If the thread has changed while we were waiting for the reloaded messages, ignore the response
      // because the user switched threads
      if (reloadThread && this.fetchingThreadID !== threadID) return false
      if (res.ok) {
        if (shouldExpectNewMessages && res.payload.messages.length === originalMessages.length) {
          // Try one more time to get the messages, in case server needed more time to save the cancelled message
          return getMessages(false)
        } else {
          const thread = res.payload.thread
          this.threadDataLoaded(threadID, res.payload.messages, refs || thread.currentReferences || [])
          if (this.afterThreadReloadCallback) {
            this.afterThreadReloadCallback(res.payload.messages)
            this.afterThreadReloadCallback = undefined
          }
          return true
        }
      } else {
        this.dispatch({
          type: 'MESSAGES_UPDATED',
          state: 'error',
          ...(res.status === 404 ? {notFound: true, missingOrgIds: res.payload?.missingOrgIds} : {}),
        })
        this.afterThreadReloadCallback = undefined
        return false
      }
    }
    const result = await getMessages(expectNewMessages)
    // Once state updates, unblock new messages from being added, if thread reloaded successfully and user didn't change active thread
    return () => {
      this.resolvePromise(result)
      this.resolvePromise = () => {}
      this.reloadingThreadPromise = undefined
    }
  }

  async fetchSharedThreadMessages(threadID: string | null) {
    if (!threadID) return

    this.dispatch({type: 'MESSAGES_UPDATED', state: 'loading'})

    const res = await this.service.listSharedThreadMessages(threadID)
    this.dispatch({type: 'FETCH_SHARED_THREAD_MESSAGES', ok: res.ok, status: res.status, shareId: threadID})

    if (res.ok) {
      this.threadDataLoaded(threadID, res.payload.messages, [])

      // Set the current model based on the model used in the shared thread's
      // most recently created message.
      await this.fetchModels()
      const lastModelID = res.payload.messages?.at(-1)?.model
      const lastModel = lastModelID && this.getChatState().availableModels?.find(m => m.id === lastModelID)
      if (lastModel) this.selectModel(lastModel)
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

  private async handleStreamingMessage(thread: CopilotChatThread, streamer: CopilotChatMessageStreamer) {
    try {
      for await (const message of streamer.stream()) {
        await this.processStreamingMessage(thread, message)
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

  private async processStreamingMessage(thread: CopilotChatThread, messageResponse: MessageStreamingResponse) {
    this.timings.firstByte ??= Date.now()
    switch (messageResponse.type) {
      case 'content': {
        this.timings.firstToken ??= Date.now()
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
            statusMessage: messageResponse.statusMessage,
          })
        }
        break
      }
      case 'clientSkillsRequest': {
        if (copilotFeatureFlags.dotcomChatClientSideSkills) {
          const state = this.getChatState()
          const selectedThread = getSelectedThread(state)
          this.skillExecutor = new SkillExecutor(
            selectedThread,
            messageResponse.toolCalls,
            params => void this.sendChatMessage(params),
            state,
            this.dispatch,
          )
          this.dispatch({
            type: 'CLIENT_SKILLS_REQUEST',
            toolCalls: messageResponse.toolCalls,
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
      case 'threadTitle': {
        this.dispatch({
          type: 'THREAD_UPDATED',
          thread: {
            ...thread,
            name: messageResponse.title,
          },
        })
        break
      }
      case 'complete': {
        // Filters out the message's references that are coming from the custom copilot agent
        messageResponse.references = filterOutCustomCopilotReferences(messageResponse.references)

        this.dispatch({
          type: 'MESSAGE_STREAMING_COMPLETED',
          messageResponse,
          timings: this.completeTiming(),
        })
        this.handleSendMessageSuccess(thread)
        if (copilotFeatureFlags.dotcomChatClientSideSkills) {
          this.skillExecutor?.setParentMessageId(messageResponse.id)
          await this.skillExecutor?.run()
        }
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
        let message = (
          <>
            This response cannot be shown because it references public code, which is restricted by{' '}
            <a href={docsURL}>your Copilot settings</a>.
          </>
        )

        if (this.hasCEorCBAccess) {
          docsURL =
            'https://docs.github.com/en/enterprise-cloud@latest/copilot/managing-copilot/managing-github-copilot-in-your-organization/managing-policies-for-copilot-in-your-organization'
          message = (
            <>
              This response cannot be shown because it references public code, which is restricted by{' '}
              <a href={docsURL}>your organization&apos;s Copilot settings</a>.
            </>
          )
        }

        return {
          type: 'publicCode',
          isError: true,
          message,
          retryable: false,
        }
      }
      case 'filtered':
        return makeNonRetryableError(ERRORS_BY_STATUS[403] || ERROR_MSG, 'filtered')
      case 'contentTooLarge':
        return makeNonRetryableError(ERRORS_BY_STATUS[413] || ERROR_MSG)
      case 'rateLimit':
        return makeBasicError(ERRORS_BY_STATUS[429] || ERROR_MSG)
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
        return makeBasicError(ERRORS_BY_STATUS[408] || ERROR_MSG)
      case 'exception':
      default:
        return makeBasicError(ERRORS_BY_TYPE[res.errorType] || ERROR_MSG)
    }
  }

  private handleSendMessageSuccess(thread: CopilotChatThread) {
    copilotLocalStorage.setSavedMessageFast(thread.id, null)
    copilotLocalStorage.clearCurrentReferences(thread.id)

    this.dispatch({type: 'WAITING_ON_COPILOT', loading: false})
  }

  private handleSendMessageError(thread: CopilotChatThread | null, error: ChatError, submittedInput?: string) {
    if (thread && submittedInput) {
      copilotLocalStorage.setSavedUserMessageOnError(thread.id, submittedInput)
    }

    // Errors get added to last found user message
    const parentMessageID =
      getActiveMessages(this.getChatState().messages).findLast(m => m.role === 'user')?.id || 'root'

    const message = buildMessage({
      role: 'assistant',
      content: '',
      mediaContent: [],
      error,
      thread,
      parentMessageID,
    })
    this.dispatch({type: 'MESSAGE_ADDED', message})
    this.dispatch({type: 'WAITING_ON_COPILOT', loading: false})
    this.dispatch({type: 'MESSAGE_STREAMING_FAILED', timings: this.completeTiming()})
  }

  async fetchModels() {
    if (modelsCache) {
      const {availableModels} = this.getChatState()
      if (!availableModels || modelsCache.length > availableModels.length) {
        this.dispatch({type: 'MODELS_LOADED', models: modelsCache})
      }
      return
    }

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
      setTimeout(
        () =>
          this.dispatch({
            type: 'THREADS_LOADING_ERROR',
            message: res.error,
            status: res.status,
          }),
        100,
      )
      return null
    }

    // There is a bit of a race condition with the THREADS_LOADING event
    // Wait 10ms before dispatching the THREADS_LOADED event
    setTimeout(() => this.dispatch({type: 'THREADS_LOADED', threads: res.payload}), 100)

    return res.payload
  }

  async fetchSharedThreads(): Promise<CopilotChatThread[] | null> {
    this.dispatch({type: 'SHARED_THREADS_LOADING'})
    const res = await this.service.fetchSharedThreads()
    if (!res.ok) {
      setTimeout(() => this.dispatch({type: 'SHARED_THREADS_LOADING_ERROR', message: res.error}), 100)
      return null
    }
    setTimeout(() => this.dispatch({type: 'SHARED_THREADS_LOADED'}), 100)

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

  async continueSharedThread(sharedID: string | null): Promise<CopilotChatDuplicate | null> {
    if (!sharedID) {
      this.dispatch({type: 'THREAD_CONTINUED_FAILED'})
      return null
    }

    this.dispatch({type: 'MESSAGES_UPDATED', state: 'loading'})

    const res = await this.service.continueSharedThread(sharedID)
    if (res.ok) {
      const {thread, messages} = res.payload
      this.dispatch({type: 'THREAD_CONTINUED', thread})
      this.dispatch({type: 'MESSAGES_UPDATED', state: 'loaded', messages})
    } else {
      return null
    }

    return res.payload
  }

  async unshareAllThreads() {
    const res = await this.service.unshareAllThreads()
    if (res.ok) {
      // Update threads in state to reflect unshared status
      const threads = Array.from(this.getChatState().threads.values())
      for (const thread of threads) {
        if (thread.sharedAt) {
          this.dispatch({
            type: 'THREAD_UPDATED',
            thread: {id: thread.id, sharedAt: undefined, sharedID: undefined},
          })
        }
      }
      return res
    } else {
      this.dispatch({
        type: 'ADD_AMBIENT_ERROR',
        message: res.error || 'Failed to unshare all threads',
      })
      return res
    }
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
      const previouslySelectedThreadID = copilotLocalStorage.selectedThreadID || undefined
      thread = await this.fetchLatestThread(previouslySelectedThreadID)
    }

    // If the thread is associated with a space, we don't want to load this in assistive mode
    // Temporary until we figure out Spaces in assistive mode
    if (thread && (isThreadOlderThan4Hours(thread) || !!thread.customCopilotID)) thread = null

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

  private async systemPrompt(mode?: CopilotChatMode): Promise<string> {
    const res = await this.service.getSystemPrompt(mode)
    return res.ok ? res.payload.prompt : ''
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

  public async fetchCustomCopilot(customCopilotID: CustomCopilotId): Promise<CustomCopilotPayload> {
    const res = await this.service.fetchCustomCopilot(customCopilotID)
    let customCopilot = {} as CustomCopilotPayload
    if (res.ok) {
      customCopilot = res.payload
    }

    return customCopilot
  }

  public async fetchCurrentRepo(repoID: number | string): Promise<CopilotChatRepo | undefined> {
    if (copilotFeatureFlags.topicsAsReferences) {
      const res = await this.service.fetchRepo(repoID)
      if (res.ok) {
        this.dispatch({type: 'ADD_REFERENCE', reference: makeRepositoryReference(res.payload), source: 'currentRepo'})
        return res.payload
      }
      return undefined
    }

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

      // Generate suggestions based on the updated implicit context.
      // This ensures suggestions are refreshed even during soft navigation between pages,
      // where the use-chat.ts hook might not be triggered.
      if (context && context.length > 0 && context[0] !== undefined) {
        this.generateSuggestions(context[0])
      }
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

  public startEditingMessage = (messageId: string) => this.dispatch({type: 'START_EDITING_MESSAGE', messageId})

  public cancelEditingMessage = () => this.dispatch({type: 'CANCEL_EDITING_MESSAGE'})

  private threadDataLoaded(
    threadId: string | null,
    messages: CopilotChatMessage[],
    references: CopilotChatReference[],
  ) {
    const {activePlugin} = this.getChatState()

    if (threadId) {
      const matchedPlugin = this.plugins.find(plugin => plugin.matchThread?.(threadId, messages, references))

      // Select or clear current plugin for new thread
      if (matchedPlugin?.id !== activePlugin) {
        this.dispatch({type: 'SELECT_PLUGIN', plugin: matchedPlugin?.id})
      }
    }

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

  public dismissEditorUpsellBanner() {
    const data = new FormData()
    data.set('copilot_editor_upsell_banner_dismissed', 'true')
    void verifiedFetch('/github-copilot/preferences', {method: 'PUT', body: data})

    this.dispatch({type: 'DISMISS_EDITOR_UPSELL_BANNER'})
  }

  // This method is only meant to be called when message was determined to be absent.
  public tryInferMessage(references: CopilotChatReference[]): [boolean, string?] {
    if (references) {
      const imageRef = references.find(ref => ref.type === 'image')
      if (imageRef) {
        return [true, 'Describe this image']
      }
    }

    return [false, undefined]
  }

  public setWrapCodeLines(value: boolean) {
    this.dispatch({type: 'SET_WRAP_CODE_LINES', value})
    copilotLocalStorage.setWrapCodeLines(value)
  }

  private completeTiming() {
    return {...this.timings, endTime: Date.now()}
  }

  /**
   * Generates a unique key for a custom copilot based on its ID.
   * This is used to manage pending threads for different custom copilots.
   * @param customCopilotId - The ID of the custom copilot, or null for the default copilot
   * @returns A string key representing the custom copilot
   */
  private getCustomCopilotKey(customCopilotId?: CustomCopilotId | null): string {
    return customCopilotId ? `${customCopilotId.owner}:${customCopilotId.id}` : 'default'
  }

  /**
   * Retrieves a thread by its ID
   * @param threadId - The ID of the thread to retrieve
   * @returns The thread with the specified ID, or null if not found
   */
  getThreadById(threadId: string | null): CopilotChatThread | null {
    if (!threadId) return null

    const state = this.getChatState()
    return state.threads.get(threadId) || null
  }

  /**
   * Gets the ID of the currently pending thread for a custom copilot.
   * This is used to keep track of the thread that is created but not yet selected,
   * especially when attaching images in the space's page
   * @param customCopilotId - The ID of the custom copilot, or null for the default copilot
   * @returns The ID of the pending thread, or null if there is no pending thread
   */
  getPendingThreadId(customCopilotId?: CustomCopilotId | null): string | null {
    const key = this.getCustomCopilotKey(customCopilotId)
    return this.pendingThreadsByCustomCopilotId.get(key) || null
  }

  /**
   * Sets the pending thread ID to the specified value.
   * This is used to keep track of the thread that is created but not yet selected,
   * especially when attaching images in the space's page.
   */
  setPendingThreadId(threadId: string | null, customCopilotId?: CustomCopilotId | null) {
    const key = this.getCustomCopilotKey(customCopilotId)
    this.pendingThreadsByCustomCopilotId.set(key, threadId)
  }

  /**
   * Removes the pending thread ID for a custom copilot.
   * This is used to clear the pending thread when it is no longer needed,
   * for example, when the thread is selected.
   * @param customCopilotId - The ID of the custom copilot, or null for the default copilot
   */
  removePendingThreadId(customCopilotId: CustomCopilotId | null | undefined) {
    const key = this.getCustomCopilotKey(customCopilotId)
    this.pendingThreadsByCustomCopilotId.delete(key)
  }

  /**
   * Selects the pending thread if it exists in the pendingThreadsByCustomCopilotId map.
   * This is used to restore the created thread and select it when we attach images
   * in the space's page.
   */
  async selectPendingThread(customCopilotId?: CustomCopilotId | null) {
    const pendingThreadId = this.getPendingThreadId(customCopilotId)
    const pendingThread = this.getThreadById(pendingThreadId)

    if (pendingThread) {
      await this.selectThread(pendingThread)
    }
  }
}

function payloadIsAttachToThread(payload: CopilotChatEventPayload) {
  return (
    payloadHasIntent(payload, [CopilotChatIntents.conversation]) && 'attachThread' in payload && payload.attachThread
  )
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
  return SUPPORTED_FUNCTIONS.includes(name)
}

function makeBasicError(message: string): ChatError {
  return {isError: true, message, type: 'basic', retryable: true}
}

function makeNonRetryableError(message: string, type?: 'filtered'): ChatError {
  return {isError: true, message, type: type || 'basic', retryable: false}
}

function setCopilotButtonAriaExpanded(entryPointId: string, ariaExpanded?: boolean) {
  const copilotButton = document.getElementById(entryPointId)
  // If it is currently collapsed, we are expanding the chat
  copilotButton?.setAttribute('aria-expanded', ariaExpanded ? 'true' : 'false')
}

/**
 * Used to abort any active downloads when references are dropped.
 * @param removedReferences - references that were removed from the current references
 */
function abortInProcessImageDownloads(removedReferences: CopilotChatReference[]) {
  for (const ref of removedReferences) {
    if (ref.type === 'image') {
      const attachment = ref.attachment
      if (attachment instanceof UploadableFileAttachment) {
        attachment.abortController.abort('Reference removed before upload completed')
      }
    }
  }
}
