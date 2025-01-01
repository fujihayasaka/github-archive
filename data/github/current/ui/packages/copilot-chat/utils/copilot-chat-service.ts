import {BlackbirdPermissionCaches} from '@github-ui/blackbird-warm-caches'
import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {blobDetectLanguage, treeListPath} from '@github-ui/paths'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import {ApiCache} from './api-cache'
import {ERROR_MSG, ERRORS_BY_STATUS, makeCAPIRequest} from './copilot-chat-helpers'
import type {
  APIResult,
  APIStreamingResult,
  AutocompleteDiscussion,
  AutocompleteIssue,
  AutocompletePullRequest,
  BlackbirdSuggestion,
  ClientSideSkillDefinition,
  CopilotChatAgent,
  CopilotChatMessage,
  CopilotChatMode,
  CopilotChatOrg,
  CopilotChatReference,
  CopilotChatRepo,
  CopilotChatSettings,
  CopilotChatThread,
  CopilotClientConfirmation,
  CopilotCustomInstructions,
  CopilotModel,
  CopilotModelPolicyState,
  CustomCopilotId,
  CustomCopilotPayload,
  Docset,
  FailedAPIResult,
  FileReference,
  IndexCustomCopilot,
  KnowledgeBasesResponse,
  MediaContentItem,
  ReferenceDetails,
  RepoFilesResult,
  SkillOptions,
  SuggestionsResponse,
  ToolCallResult,
} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'
import {copilotLocalStorage} from './copilot-local-storage'
import {filterOutCustomCopilotReferences} from './custom-copilots-references-helpers'
import {getCopilotExperiments} from './experiments'
import {generateDefaultModel} from './models'

const BLACKBIRD_SUGGESTION_KIND = 'SUGGESTION_KIND_SYMBOL'
const HYDRATABLE_REFERENCE_TYPES = new Set(['snippet', 'file', 'symbol', 'docset', 'repository'])
const TRUNCATED_MSG = 'Content was truncated. Use the API to get full content.'
const MAX_BYTES = 16 * 1000

type ListMessagesPayload = {
  thread: CopilotChatThread
  messages: CopilotChatMessage[]
}

type ListMessagesErrorPayload = {
  missingOrgIds: number[]
}

type DuplicateThreadPayload = {
  thread: CopilotChatThread
  messages: CopilotChatMessage[]
}

type FeedbackPayload = {
  feedback?: string
  textResponse?: string
  feedbackChoice?: string[]
  isContactedChecked?: string | null
  messageId: string
  threadId: string | undefined
}

type APIPayload = CreateMessagePayload

export interface CreateMessageStreamingParams {
  threadID: string
  messageID: string
  content: string
  intent: string
  mode: string
  references: CopilotChatReference[]
  context: CopilotChatReference[]
  confirmations: CopilotClientConfirmation[]
  customInstructions?: string[] // TODO: Remove this in favor of `copilotCustomInstructions` once the CAPI change has been implemented
  copilotCustomInstructions?: CopilotCustomInstructions[]
  model?: string
  customCopilotID: CustomCopilotId | null
  parentMessageID?: string
  tools?: ClientSideSkillDefinition[]
  clientToolResults?: ToolCallResult[]
  signal?: AbortSignal
  mediaContent: MediaContentItem[]
  skillOptions?: SkillOptions
}

type CreateMessagePayload = {
  responseMessageID?: string
  content: string
  intent: string
  references: CopilotChatReference[]
  currentURL: string
  mediaContent: MediaContentItem[]
  streaming?: boolean
  context: CopilotChatReference[]
  confirmations: CopilotClientConfirmation[]
  customInstructions?: string[]
  copilotCustomInstructions?: CopilotCustomInstructions[]
  model?: string
  mode?: string
  settings?: CopilotChatSettings
  customCopilotID?: number | null
  customCopilotOwner?: string | null
  parentMessageID?: string
  tools?: ClientSideSkillDefinition[]
  clientToolResults?: ToolCallResult[]
  skillOptions?: SkillOptions
  pageContext?: string
}

interface FetchThreadsParams {
  /* Filter threads to just those with the specified name, case sensitive */
  name?: string | undefined | null
  shared?: boolean
}

interface GetSystemPromptPayloadResponse {
  prompt: string
}

export class CopilotChatService {
  apiURL: string
  urlPathPrefix = '/github-copilot/chat'
  docsetsPromise: Promise<APIResult<KnowledgeBasesResponse>> | undefined = undefined
  repoDetailsCache = new Map<number | string, CopilotChatRepo>()
  listMessagesCache: ListMessagesPayload | undefined = undefined
  copilotAuthTokenProvider: CopilotAuthTokenProvider
  blackbirdCaches: BlackbirdPermissionCaches = new BlackbirdPermissionCaches()
  realIp: string
  apiVersion: string | undefined = undefined

  constructor(apiURL: string, ssoOrgs: CopilotChatOrg[], realIp?: string, apiVersion?: string) {
    this.apiURL = apiURL
    this.copilotAuthTokenProvider = new CopilotAuthTokenProvider(ssoOrgs.map(org => org.id))
    this.realIp = realIp || ''
    this.apiVersion = apiVersion
  }

  async fetchThreads(params: FetchThreadsParams = {}): Promise<APIResult<CopilotChatThread[]>> {
    const queryParams = new URLSearchParams()
    if (typeof params.name === 'string') queryParams.set('name', params.name)
    const pathWithParams = `/threads?${queryParams.toString()}`
    const res = await this.makeCAPIRequest(pathWithParams, 'GET')
    if (!res.ok) return res as FailedAPIResult

    const payload: CopilotChatThread[] = (await res.json()).threads || []
    return {status: res.status, ok: true, payload}
  }

  async fetchSharedThreads(): Promise<APIResult<CopilotChatThread[]>> {
    const res = await this.makeCAPIRequest('/threads?shared', 'GET')
    if (!res.ok) return res as FailedAPIResult

    const payload: CopilotChatThread[] = (await res.json()).threads || []
    return {status: res.status, ok: true, payload}
  }

  // Hydrates the thread based on the given ID.
  // If the thread for the given ID is not found or the id is not provided, returns the most recently updated thread
  async fetchLatestThread(threadId?: string): Promise<APIResult<CopilotChatThread | null>> {
    const queryParams = new URLSearchParams()
    if (typeof threadId === 'string') queryParams.set('thread_id', threadId)
    const res = await this.makeCAPIRequest(`/threads/latest?${queryParams.toString()}`, 'GET')
    if (!res.ok) return res as FailedAPIResult

    const payload: CopilotChatThread | null = (await res.json()).thread
    return {status: res.status, ok: true, payload}
  }

  async createThread(customCopilotId?: CustomCopilotId | null): Promise<APIResult<CopilotChatThread>> {
    const body = {custom_copilot_id: customCopilotId?.id, custom_copilot_owner: customCopilotId?.owner}

    const res = await this.makeCAPIRequest(`/threads`, 'POST', body)
    if (!res.ok) return res as FailedAPIResult

    const payload: CopilotChatThread = (await res.json()).thread
    return {status: res.status, ok: true, payload}
  }

  async deleteThread(threadID: string): Promise<APIResult<null>> {
    const res = await this.makeCAPIRequest(`/threads/${threadID}`, 'DELETE')
    if (!res.ok) return res as FailedAPIResult

    return {status: res.status, ok: true, payload: null}
  }

  async deleteAllThreads(body: {threadIDs: string[]}): Promise<APIResult<null>> {
    const res = await this.makeCAPIRequest(`/threads`, 'DELETE', body)
    if (!res.ok) return res as FailedAPIResult

    return {status: res.status, ok: true, payload: null}
  }

  async renameThread(threadID: string, newName: string): Promise<APIResult<string>> {
    const body = {generate: false, name: newName}

    const res = await this.makeCAPIRequest(`/threads/${threadID}/name`, 'PATCH', body)
    if (!res.ok) return res as FailedAPIResult

    const payload: string = (await res.json()).name || ''
    return {status: res.status, ok: true, payload}
  }

  async clearThread(threadID: string): Promise<APIResult<null>> {
    const res = await this.makeCAPIRequest(`/threads/${threadID}/clear`, 'PATCH')
    if (!res.ok) return res as FailedAPIResult

    return {status: res.status, ok: true, payload: null}
  }

  async shareThread(threadID: string, latestShareableMessageID: string): Promise<APIResult<CopilotChatThread>> {
    const body = {shared_message_id: latestShareableMessageID}

    const res = await this.makeCAPIRequest(`/threads/${threadID}/share`, 'PATCH', body)
    if (!res.ok) return res as FailedAPIResult

    const payload: CopilotChatThread = (await res.json()).thread
    return {status: res.status, ok: true, payload}
  }

  async unshareThread(threadID: string): Promise<APIResult<CopilotChatThread>> {
    const res = await this.makeCAPIRequest(`/threads/${threadID}/unshare`, 'PATCH')
    if (!res.ok) return res as FailedAPIResult

    const payload: CopilotChatThread = (await res.json()).thread
    return {status: res.status, ok: true, payload}
  }

  async unshareAllThreads(): Promise<APIResult<null>> {
    const res = await this.makeCAPIRequest(`/threads/unshare`, 'POST')
    if (!res.ok) return res as FailedAPIResult
    return {status: res.status, ok: true, payload: null}
  }

  async continueSharedThread(sharedID: string): Promise<APIResult<DuplicateThreadPayload>> {
    const res = await this.makeCAPIRequest(`/shared/${sharedID}/duplicate`, 'POST')
    if (!res.ok) return res as FailedAPIResult

    const payload: DuplicateThreadPayload = await res.json()
    return {status: 200, ok: true, payload}
  }

  async generateThreadName(threadID: string): Promise<APIResult<string>> {
    const body = {generate: true, name: ''}

    const res = await this.makeCAPIRequest(`/threads/${threadID}/name`, 'PATCH', body)
    if (!res.ok) return res as FailedAPIResult

    const payload: string = (await res.json()).name || ''
    return {status: res.status, ok: true, payload}
  }

  async getSystemPrompt(mode?: CopilotChatMode): Promise<APIResult<GetSystemPromptPayloadResponse>> {
    const res = await this.makeCAPIRequest(`/system_prompt/${mode}`, 'GET')
    if (!res.ok) return res as FailedAPIResult

    const payload: GetSystemPromptPayloadResponse = await res.json()
    return {status: res.status, ok: true, payload}
  }

  async listMessages(threadID: string): Promise<APIResult<ListMessagesPayload, ListMessagesErrorPayload>> {
    if (this.listMessagesCache?.thread.id === threadID) {
      return {status: 200, ok: true, payload: this.listMessagesCache}
    }

    const res = await this.makeCAPIRequest(`/threads/${threadID}/messages`, 'GET')
    if (isFailedApiResult(res)) {
      if (
        res.status === 404 &&
        res.response?.headers.has('Content-Type') &&
        res.response.headers.get('Content-Type') === 'application/json'
      ) {
        const payload = (await res.response.json()) as ListMessagesErrorPayload
        return {...res, payload}
      } else {
        return res
      }
    }

    const payload: ListMessagesPayload = await res.json()

    // Filter out the references of the messages that are coming from the custom copilot agent
    // to avoid showing them in the UI
    if (Array.isArray(payload.messages)) {
      payload.messages = payload.messages.map((message: CopilotChatMessage) => {
        message.references = filterOutCustomCopilotReferences(message.references)
        return message
      })
    }

    this.listMessagesCache = payload
    return {status: res.status, ok: true, payload}
  }

  async listSharedThreadMessages(sharedID: string): Promise<APIResult<ListMessagesPayload>> {
    const res = await this.makeCAPIRequest(`/shared/${sharedID}/messages`, 'GET')
    if (!res.ok) return res as FailedAPIResult

    const payload = await res.json()
    return {status: res.status, ok: true, payload}
  }

  async createMessage(
    threadID: string,
    content: string,
    mediaContent: MediaContentItem[],
    intent: string,
    references: CopilotChatReference[],
    customInstructions?: string[],
    model?: string,
  ): Promise<APIResult<CopilotChatMessage>> {
    this.listMessagesCache = undefined
    const res = await this.makeCAPIRequest(`/threads/${threadID}/messages`, 'POST', {
      content,
      mediaContent,
      intent,
      references,
      currentURL: window.location.href,
      customInstructions,
      model,
      settings: copilotLocalStorage.settings ?? undefined,
    })
    if (!res.ok) return res as FailedAPIResult

    const payload: CopilotChatMessage = (await res.json()).message
    return {status: res.status, ok: true, payload}
  }

  async createMessageStreaming({
    threadID,
    messageID,
    content,
    mediaContent,
    intent,
    mode,
    references,
    context,
    confirmations,
    customInstructions,
    model,
    customCopilotID,
    parentMessageID,
    tools,
    clientToolResults,
    signal,
    skillOptions,
  }: CreateMessageStreamingParams): Promise<APIStreamingResult> {
    this.listMessagesCache = undefined

    const customCopilotsModeEnabled = isFeatureEnabled('custom_copilots_capi_mode')

    if (customCopilotsModeEnabled && customCopilotID) {
      mode = 'custom-copilots'
    }

    // Scrape the DOM for page context if the FF is on
    const shouldUsePageContext =
      copilotFeatureFlags.domPageContext && mode !== 'immersive' && mode !== 'custom-copilots'

    const pageContext = shouldUsePageContext ? extractPageContext() : undefined
    const body: CreateMessagePayload = {
      responseMessageID: messageID,
      content,
      intent,
      references,
      context,
      currentURL: window.location.href,
      streaming: true,
      confirmations,
      customInstructions,
      model,
      mode,
      settings: copilotLocalStorage.settings ?? undefined,
      customCopilotID: customCopilotID?.id,
      customCopilotOwner: customCopilotID?.owner,
      parentMessageID,
      tools,
      clientToolResults,
      mediaContent,
      skillOptions,
      pageContext,
    }

    const cleanedQueryParams = this.processQueryParams(new URLSearchParams(window.location.search))

    const res = await this.makeCAPIRequest(
      `/threads/${threadID}/messages?${cleanedQueryParams.toString()}`,
      'POST',
      body,
      true,
      undefined,
      signal,
    )
    if (!res.ok) return res as FailedAPIResult

    return {status: res.status, ok: true, response: res}
  }

  processQueryParams(queryParams: URLSearchParams): URLSearchParams {
    const allowedParams = ['instruction_prompt']

    const filteredParams = new URLSearchParams()

    for (const [key, value] of queryParams) {
      if (allowedParams.includes(key)) {
        filteredParams.append(key, value)
      }
    }

    return filteredParams
  }

  async listModels(): Promise<APIResult<CopilotModel[]>> {
    const basePath = '' // Exclude the default /github/chat prefix
    const res = await this.makeCAPIRequest(`/models`, 'GET', undefined, false, basePath)
    if (!res.ok) return res as FailedAPIResult

    const modelsResponse = (await res.json()) as {data: CopilotModel[]}

    return {status: res.status, ok: true, payload: modelsResponse.data}
  }

  async setModelPolicyState(modelID: string, state: CopilotModelPolicyState): Promise<void> {
    const basePath = '' // Exclude the default /github/chat prefix
    const res = await this.makeCAPIRequest(`/models/${modelID}/policy`, 'POST', {state}, false, basePath)
    if (!res.ok) return Promise.reject(new Error(`Failed to update model policy state: ${res.status}`))
  }

  /** Get the model's response for a given prompt. */
  async getSimpleCompletion(prompt: string, model?: string): Promise<APIResult<string>> {
    const defaultModel = generateDefaultModel()
    const selectedModel = model ?? defaultModel.id
    const messages = [
      {
        role: 'user',
        content: prompt,
      },
    ]

    const response = await this.makeCAPIRequest(
      '/chat/completions',
      'POST',
      {
        messages,
        selectedModel,
        stream: false,
      },
      false,
      '',
    )

    if (!response.ok) return response as FailedAPIResult

    const payload = (await response.json()).choices[0]?.message?.content || ''
    return {status: response.status, ok: true, payload}
  }

  async sendFeedback({feedback, feedbackChoice, messageId, threadId, textResponse}: FeedbackPayload) {
    const body = {
      feedback,
      feedback_choice: feedbackChoice,
      message_id: messageId,
      thread_id: threadId,
      text_response: textResponse,
    }
    const res = await this.makeDotcomRequest(`${this.urlPathPrefix}/feedback`, 'POST', body)
    if (!res.ok) return res as FailedAPIResult

    return {status: res.status, ok: true, payload: null}
  }

  async listDocsets(): Promise<APIResult<Docset[]>> {
    const response = await this.fetchDocsetsResponse()
    if (!response.ok) return response
    return {status: 200, ok: true, payload: response.payload.knowledgeBases}
  }

  // The response from the server will be null if the user has access to one or more knowledge bases. That is because
  // we only use the administratedCopilotEnterpriseOrganizations if there are no knowledge bases. So to save executing a bunch
  // of queries to get administrated orgs and check if they have Copilot Enterprise we just return null in that case.
  //
  // We could have made a separate API endpoint to get a list of administratedCopilotEnterpriseOrganizations and only called it
  // if there are no knowledge bases, but this would result in a layout shift when the response comes in and we render
  // a different set of HTML if there are orgs.
  //
  // In the future we may need a separate endpoint if we need administratedCopilotEnterpriseOrganizations elsewhere but for now
  // this is a much higher performance way to get this information without layout shifting.
  //
  // See the issue this fixes: https://github.com/github/copilot-core-productivity/issues/1443
  async listAdministratedCopilotEnterpriseOrganizations(): Promise<APIResult<CopilotChatOrg[] | null>> {
    const response = await this.fetchDocsetsResponse()
    if (!response.ok) return response
    return {status: 200, ok: true, payload: response.payload.administratedCopilotEnterpriseOrganizations}
  }

  fetchDocsetsResponse(): Promise<APIResult<KnowledgeBasesResponse>> {
    if (!this.docsetsPromise) {
      this.docsetsPromise = this.docsetRequestPromise()
    }
    return this.docsetsPromise
  }

  async docsetRequestPromise(): Promise<APIResult<KnowledgeBasesResponse>> {
    const res = await this.makeDotcomRequest(`/github-copilot/docs/docsets`, 'GET')
    if (!res.ok) return res as FailedAPIResult
    const payload = (await res.json()) as KnowledgeBasesResponse
    return {status: 200, ok: true, payload}
  }

  async deleteDocset(docset: Docset) {
    const res = await this.makeDotcomRequest(`/copilot/docsets/${docset.id}`, 'DELETE')
    if (!res.ok) return res as FailedAPIResult
    return {status: res.status, ok: true, payload: null}
  }

  async listRepoFiles(repo: CopilotChatRepo, includeDirectories: boolean = false): Promise<APIResult<RepoFilesResult>> {
    const path = treeListPath({repo, commitOid: repo.commitOID, includeDirectories})
    return this.repoFilesCache.get(path)
  }

  private listRepoFilesImpl = async (path: string): Promise<APIResult<RepoFilesResult>> => {
    const res = await this.makeDotcomRequest(path, 'GET')
    if (!res.ok) return res as FailedAPIResult

    const payload = await res.json()

    return {status: 200, ok: true, payload}
  }
  private repoFilesCache = new ApiCache(this.listRepoFilesImpl)

  async querySymbols(repo: CopilotChatRepo, query: string): Promise<APIResult<BlackbirdSuggestion[]>> {
    await this.blackbirdCaches.setupWarmCachesLoop()
    return this.querySymbolsCache.get(repo.ownerLogin, repo.name, query)
  }

  private querySymbolsImpl = async (
    ownerLogin: string,
    repo: string,
    query: string,
  ): Promise<APIResult<BlackbirdSuggestion[]>> => {
    const response = await this.makeDotcomRequest(
      `/search/suggestions?query=repo:${ownerLogin}/${repo} ${query}`,
      'GET',
    )

    if (!response.ok) {
      return response as FailedAPIResult
    }

    const payload = (await response.json()) as SuggestionsResponse

    return {
      status: 200,
      ok: true,
      payload: payload.suggestions.filter(suggestion => suggestion.kind === BLACKBIRD_SUGGESTION_KIND),
    }
  }
  private querySymbolsCache = new ApiCache(this.querySymbolsImpl)

  async fetchImplicitContext(
    url: string,
    owner: string,
    repo: string,
  ): Promise<APIResult<CopilotChatReference | CopilotChatReference[]>> {
    const response = await this.makeDotcomRequest(
      `${this.urlPathPrefix}/implicit-context/${owner}/${repo}/${encodeURIComponent(url)}`,
      'GET',
    )

    if (!response.ok) return response as FailedAPIResult

    return {
      status: response.status,
      ok: response.ok,
      payload: await response.json(),
    }
  }

  async fetchRepo(repoID: number | string): Promise<APIResult<CopilotChatRepo>> {
    let payload: CopilotChatRepo
    if (this.repoDetailsCache.has(repoID)) {
      payload = this.repoDetailsCache.get(repoID)!
    } else {
      const res = await this.makeDotcomRequest(`${this.urlPathPrefix}/repositories/${repoID}`, 'GET')
      if (!res.ok) return res as FailedAPIResult

      payload = await res.json()
      this.repoDetailsCache.set(repoID, payload)
    }

    return {status: 200, ok: true, payload}
  }

  async listAgents(agentsPath: string): Promise<APIResult<CopilotChatAgent[]>> {
    const res = await verifiedFetchJSON(agentsPath)
    if (!res.ok) return {status: res.status, ok: false, error: ERRORS_BY_STATUS[res.status] || ERROR_MSG}
    const payload = await res.json()
    return {status: res.status, ok: res.ok, payload}
  }

  async listCustomCopilots(): Promise<APIResult<IndexCustomCopilot[]>> {
    const res = await verifiedFetchJSON(`${this.urlPathPrefix}/custom_copilots`)
    if (!res.ok) return {status: res.status, ok: false, error: ERRORS_BY_STATUS[res.status] || ERROR_MSG}
    const payload = await res.json()
    return {status: res.status, ok: true, payload}
  }

  async fetchCustomCopilot(customCopilotID: CustomCopilotId): Promise<APIResult<CustomCopilotPayload>> {
    let url: string
    const {owner, id} = customCopilotID
    if (owner) {
      url = `${this.urlPathPrefix}/custom_copilots/${owner}/${id}`
    } else {
      url = `${this.urlPathPrefix}/custom_copilots/${id}`
    }
    const res = await verifiedFetchJSON(url)
    if (!res.ok) return {status: res.status, ok: false, error: ERRORS_BY_STATUS[res.status] || ERROR_MSG}
    const payload = await res.json()
    return {status: res.status, ok: true, payload}
  }

  async hydrateReference<T extends CopilotChatReference>(reference: T): Promise<APIResult<ReferenceDetails<T>>> {
    if (!HYDRATABLE_REFERENCE_TYPES.has(reference.type)) {
      return {
        status: 204,
        ok: true,
        payload: reference as ReferenceDetails<T>,
      }
    }
    const response = await this.makeDotcomRequest(`${this.urlPathPrefix}/reference_details`, 'POST', {reference})

    if (!response.ok) return response as FailedAPIResult

    return {
      status: response.status,
      ok: response.ok,
      payload: await response.json(),
    }
  }

  async fetchLanguageForFileReference(reference: FileReference) {
    const {repoOwner: ownerLogin, repoName: name} = reference
    const path = window.btoa(reference.path)
    const repo = {ownerLogin, name}
    const fetchPath = blobDetectLanguage(repo, path, true)

    const response = await this.makeDotcomRequest(fetchPath, 'GET')

    if (!response.ok) return response as FailedAPIResult

    return {
      status: response.status,
      ok: response.ok,
      payload: await response.json(),
    }
  }

  async fetchAutocompleteIssues(repository: string, query: string) {
    const response = await this.makeDotcomRequest(
      `/copilot/chat/autocomplete/issues?repo=${repository}&q=${query}`,
      'GET',
    )
    return response.ok ? ((await response.json()) as AutocompleteIssue[]) : []
  }

  async fetchAutocompletePullRequests(repository: string, query: string) {
    const response = await this.makeDotcomRequest(
      `/copilot/chat/autocomplete/pulls?repo=${repository}&q=${query}`,
      'GET',
    )
    return response.ok ? ((await response.json()) as AutocompletePullRequest[]) : []
  }

  async fetchAutocompleteDiscussions(repository: string, query: string) {
    const response = await this.makeDotcomRequest(
      `/copilot/chat/autocomplete/discussions?repo=${repository}&q=${query}`,
      'GET',
    )
    return response.ok ? ((await response.json()) as AutocompleteDiscussion[]) : []
  }

  protected async makeDotcomRequest(
    path: string,
    method: 'GET' | 'POST' | 'DELETE' | 'PATCH' | 'PUT',
    body?: object | APIPayload,
  ): Promise<Response | FailedAPIResult> {
    const headers: {[key: string]: string} = {}
    for (const exp of getCopilotExperiments()) {
      const components = exp.split('=')
      const name = components[0]?.replaceAll('_', '-')
      let value = '1'
      if (components.length > 1) {
        value = components[1]!
      }
      headers[`X-Experiment-${name}`] = value
    }

    const token = await this.copilotAuthTokenProvider.getAuthToken()
    headers['X-Copilot-Api-Token'] = token.value

    try {
      const res = await verifiedFetchJSON(path, {method, body, headers})
      if (res.ok) return res
      return {status: res.status, ok: false, error: ERRORS_BY_STATUS[res.status] || ERROR_MSG}
    } catch {
      return {status: 500, ok: false, error: ERROR_MSG}
    }
  }

  private get directConnectConfiguration() {
    return process.env.NODE_ENV === 'development'
      ? {integrationID: 'copilot-chat-dev'}
      : {integrationID: 'copilot-chat'}
  }

  protected async makeCAPIRequest(
    path: string,
    method: 'GET' | 'POST' | 'DELETE' | 'PATCH',
    body?: object | APIPayload,
    streamingResponse = false,
    basePath = '/github/chat',
    signal?: AbortSignal,
  ): Promise<Response | FailedAPIResult> {
    const baseURL = this.apiURL
    const token = await this.copilotAuthTokenProvider.getAuthToken()
    // When the feature flag is ebabled, this.apiVersion will be truthly
    return await makeCAPIRequest({
      basePath: baseURL + basePath,
      path,
      method,
      body,
      streamingResponse,
      authToken: token,
      integrationId: this.directConnectConfiguration.integrationID,
      realIp: this.realIp,
      signal,
      apiVersion: this.apiVersion,
    })
  }
}

function isFailedApiResult(res: Response | FailedAPIResult): res is FailedAPIResult {
  return !res.ok
}

// Attempt to retain some structure from the dom content
const extractStructuredContent = (element: Element): string | null => {
  const tagName = element.tagName.toLowerCase()
  const text = element.textContent

  if (!text || !text.trim()) {
    return null
  }

  const trimmedText = text.trim()

  // Add semantic markers based on element type
  switch (tagName) {
    case 'h1':
      return `# ${trimmedText}`
    case 'h2':
      return `## ${trimmedText}`
    case 'h3':
      return `### ${trimmedText}`
    case 'h4':
      return `#### ${trimmedText}`
    case 'p':
      return trimmedText
    case 'li':
      return `• ${trimmedText}`
    case 'code':
      return `\`${trimmedText}\``
    case 'pre':
      return `\`\`\`\n${trimmedText}\n\`\`\``
    case 'blockquote':
      return `> ${trimmedText}`
    default:
      return trimmedText
  }
}

function extractPageContext(): string {
  // Try to find the most semantically relevant content containers
  const mainContent = document.querySelector('main') || document.body
  const contentClone = mainContent.cloneNode(true) as HTMLElement

  // Remove scripts, styles, and other non-content elements
  const elementsToRemove = [
    'script',
    'style',
    'svg',
    'iframe',
    'textarea',
    '.js-header-wrapper',
    '.footer',
    '.sr-only',
    '.react-code-file-contents',
  ]

  for (const selector of elementsToRemove) {
    for (const el of contentClone.querySelectorAll(selector)) {
      el.remove()
    }
  }

  // Remove hidden or empty elements
  for (const el of contentClone.querySelectorAll('*')) {
    if (!el.textContent?.trim()) {
      el.remove()
      continue
    }
    const style = window.getComputedStyle(el)
    if (style.display === 'none' || style.visibility === 'hidden') {
      el.remove()
    }
  }

  // Extract structured content
  const blocks = contentClone.querySelectorAll('p, h1, h2, h3, h4, li, td, th, blockquote, pre, code:not(pre code)')
  const lines: string[] = []

  for (const block of blocks) {
    const formattedText = extractStructuredContent(block)
    if (formattedText) {
      lines.push(formattedText)
    }
  }

  const text = lines.join('\n')
  const cleaned = text.length <= MAX_BYTES ? text : `${text.substring(0, MAX_BYTES)}\n${TRUNCATED_MSG}`

  // Keep some whitespace normalization, but not collapse all whitespace
  return cleaned.replace(/\s{2,}/g, ' ').trim()
}
