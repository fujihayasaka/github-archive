import {BlackbirdPermissionCaches} from '@github-ui/blackbird-warm-caches'
import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {blobDetectLanguage, treeListPath} from '@github-ui/paths'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import {ApiCache} from './api-cache'
import {ERROR_MSG, ERRORS, makeCAPIRequest} from './copilot-chat-helpers'
import type {
  APIResult,
  APIStreamingResult,
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
  CopilotModel,
  CopilotModelPolicyState,
  CustomCopilot,
  Docset,
  FailedAPIResult,
  FileReference,
  KnowledgeBasesResponse,
  MediaContentItem,
  ReferenceDetails,
  RepoFilesResult,
  SuggestionsResponse,
  ToolCallResult,
} from './copilot-chat-types'
import {copilotLocalStorage} from './copilot-local-storage'
import {getCopilotExperiments} from './experiments'

const BLACKBIRD_SUGGESTION_KIND = 'SUGGESTION_KIND_SYMBOL'
const HYDRATABLE_REFERENCE_TYPES = new Set(['snippet', 'file', 'symbol', 'docset', 'repository'])

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
  customInstructions?: string[]
  model?: string
  customCopilotID?: number | null
  parentMessageID?: string
  tools?: ClientSideSkillDefinition[]
  clientToolResults?: ToolCallResult[]
  signal?: AbortSignal
  mediaContent: MediaContentItem[]
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
  model?: string
  mode?: string
  settings?: CopilotChatSettings
  customCopilotID?: number | null
  parentMessageID?: string
  tools?: ClientSideSkillDefinition[]
  clientToolResults?: ToolCallResult[]
}

interface FetchThreadsParams {
  /* Filter threads to just those with the specified name, case sensitive */
  name?: string | undefined | null
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

  constructor(apiURL: string, ssoOrgs: CopilotChatOrg[], realIp?: string) {
    this.apiURL = apiURL
    this.copilotAuthTokenProvider = new CopilotAuthTokenProvider(ssoOrgs.map(org => org.id))
    this.realIp = realIp || ''
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

  async createThread(customCopilotId?: number | null): Promise<APIResult<CopilotChatThread>> {
    const body = {custom_copilot_id: customCopilotId}

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

  async deleteCopilotSpace(copilotId: number): Promise<APIResult<null>> {
    const res = await verifiedFetchJSON(`${this.urlPathPrefix}/custom_copilots/${copilotId}`, {method: 'DELETE'})
    if (!res.ok) return res as unknown as FailedAPIResult

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

    const payload = await res.json()
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
  }: CreateMessageStreamingParams): Promise<APIStreamingResult> {
    this.listMessagesCache = undefined
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
      customCopilotID,
      parentMessageID,
      tools,
      clientToolResults,
      mediaContent,
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
    if (!res.ok) return {status: res.status, ok: false, error: ERRORS[res.status] || ERROR_MSG}
    const payload = await res.json()
    return {status: res.status, ok: res.ok, payload}
  }

  async listCustomCopilots(): Promise<APIResult<CustomCopilot[]>> {
    const res = await verifiedFetchJSON(`${this.urlPathPrefix}/custom_copilots`)
    if (!res.ok) return {status: res.status, ok: false, error: ERRORS[res.status] || ERROR_MSG}
    const payload = await res.json()
    return {status: res.status, ok: true, payload}
  }

  async fetchCustomCopilot(customCopilotID: number): Promise<APIResult<CustomCopilot>> {
    const res = await verifiedFetchJSON(`${this.urlPathPrefix}/custom_copilots/${customCopilotID}`)
    if (!res.ok) return {status: res.status, ok: false, error: ERRORS[res.status] || ERROR_MSG}
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
      return {status: res.status, ok: false, error: ERRORS[res.status] || ERROR_MSG}
    } catch {
      return {status: 500, ok: false, error: ERROR_MSG}
    }
  }

  private get directConnectConfiguration() {
    return process.env.NODE_ENV === 'development'
      ? {integrationID: 'copilot-chat-dev'}
      : {integrationID: 'copilot-chat'}
  }

  private async makeCAPIRequest(
    path: string,
    method: 'GET' | 'POST' | 'DELETE' | 'PATCH',
    body?: object | APIPayload,
    streamingResponse = false,
    basePath = '/github/chat',
    signal?: AbortSignal,
  ): Promise<Response | FailedAPIResult> {
    const baseURL = this.apiURL
    const token = await this.copilotAuthTokenProvider.getAuthToken()

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
    })
  }
}

function isFailedApiResult(res: Response | FailedAPIResult): res is FailedAPIResult {
  return !res.ok
}
