import type {AuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {addUrlToHistoryStack} from '@github-ui/history'
import {repositoryTreePath} from '@github-ui/paths'

import {getCommandSuggestions} from '../components/task-oriented-assistive/commands'
import type {
  BlackbirdSuggestion,
  ChatError,
  CopilotAgentConfirmation,
  CopilotChatMessage,
  CopilotChatMode,
  CopilotChatReference,
  CopilotChatRepo,
  CopilotChatSuggestions,
  CopilotChatThread,
  CopilotClientConfirmation,
  CopilotCustomInstructions,
  Docset,
  DocsetReference,
  FailedAPIResult,
  FileChangesReference,
  FileDiffReference,
  FileReference,
  FolderReference,
  GitHubAgentReference,
  ImageReference,
  IssueReference,
  LoadingReference,
  MediaContentItem,
  OrgInstructionsReference,
  PullRequestReference,
  RepositoryReference,
  SkillOptions,
  SnippetReference,
  SuggestionSymbolReference,
  ToolCallResult,
  TreeComparisonReference,
  WebSearchResultReference,
} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'
import {getCopilotExperiments} from './experiments'
import {threadSuggestions} from './prompts'

export const COPILOT_PATH = '/copilot'

export const COPILOT_SPACES_PATH = `${COPILOT_PATH}/spaces`
export const COPILOT_SPACES_NEW_PATH = `${COPILOT_SPACES_PATH}/new`

export const UPGRADE_PLAN_URL = 'https://github.com/features/copilot#pricing'
export const UPGRADE_TO_PRO_PLAN_URL = 'https://github.com/github-copilot/pro'
export const ENABLE_ADDITIONAL_REQUESTS_URL = 'https://github.com/settings/billing/budgets'
export const MANAGE_BILLING_URL = 'https://github.com/settings/billing'
export const FREE_QUOTA_TRIGGER = 50
export const PREMIUM_QUOTA_TRIGGER = 20

export const ERRORS_BY_STATUS: {[key: number]: string} = {
  400: 'This message could not be processed.',
  401: 'You’re not authorized to use Copilot.',
  403: 'Access denied. You do not have permission to view this.',
  404: 'Resource not found. Please try again.',
  408: 'Your network connection was interrupted. Please try again.',
  413: 'Message too large. Please shorten it or remove some references and try again.',
  429: 'GitHub API rate limit exceeded. Please wait and try again.',
}

export const ERRORS_BY_TYPE: {[type: string]: string} = {
  extensionForbidden:
    'Copilot extensions can’t be used in shared conversations. Please unshare the conversation and try again.',
}

export const ERROR_MSG = "I'm sorry but there was an error. Please try again."

export async function makeCAPIRequest({
  authToken,
  basePath,
  body,
  integrationId,
  method,
  path,
  streamingResponse = false,
  realIp,
  signal,
  apiVersion,
}: {
  authToken: AuthToken
  basePath: string
  body?: object
  integrationId: string
  method: 'GET' | 'POST' | 'DELETE' | 'PATCH'
  path: string
  streamingResponse: boolean
  realIp?: string
  signal?: AbortSignal
  apiVersion?: string
}): Promise<Response | FailedAPIResult> {
  try {
    const headers: {[key: string]: string} = {
      Authorization: authToken.authorizationHeaderValue,
      'copilot-integration-id': integrationId,
    }
    for (const exp of getCopilotExperiments()) {
      const components = exp.split('=')
      const name = components[0]?.replaceAll('_', '-')
      let value = '1'
      if (components.length > 1) {
        value = components[1]!
      }
      headers[`X-Experiment-${name}`] = value
    }
    if (apiVersion) {
      headers['X-GitHub-Api-Version'] = apiVersion
    }

    if (streamingResponse) {
      headers['Content-Type'] = 'text/event-stream'
    }

    if (realIp) {
      headers['X-Real-IP'] = realIp
    }

    const res = await fetch(basePath + path, {
      method,
      mode: 'cors',
      cache: 'no-cache',
      headers,
      body: JSON.stringify(body),
      signal,
    })

    if (res.ok) return res
    return {status: res.status, ok: false, error: ERRORS_BY_STATUS[res.status] || ERROR_MSG, response: res}
  } catch {
    return {status: 500, ok: false, error: ERROR_MSG}
  }
}

export function buildMessage({
  role,
  content,
  mediaContent,
  error,
  references = [],
  thread,
  confirmationResponses,
  clientSkillConfirmations,
  clientToolResults,
  parentMessageID,
  skillOptions,
}: {
  role: 'user' | 'assistant'
  content: string
  mediaContent: MediaContentItem[]
  error?: ChatError
  references?: CopilotChatReference[]
  thread?: CopilotChatThread | null
  confirmationResponses?: CopilotClientConfirmation[]
  clientSkillConfirmations?: CopilotAgentConfirmation[]
  clientToolResults?: ToolCallResult[]
  parentMessageID?: string
  skillOptions?: SkillOptions
}): CopilotChatMessage {
  return {
    id: crypto.randomUUID(),
    threadID: thread?.id || 'temp',
    role,
    content,
    mediaContent,
    createdAt: new Date().toISOString(),
    error,
    references,
    skillExecutions: [],
    clientConfirmations: confirmationResponses,
    clientToolResults,
    confirmations: clientSkillConfirmations,
    parentMessageID,
    clientSide: true, // Default to true until server confirms storage in MESSAGE_STREAMING_COMPLETED
    skillOptions,
  }
}

export function threadName(thread: CopilotChatThread | undefined | null): string {
  return thread?.name || 'New conversation'
}

export function referenceName(ref: CopilotChatReference): string {
  switch (ref.type) {
    case 'figma':
      return ref.title || ref.url
    case 'file':
      return fileRefName(ref)
    case 'folder':
      return fileRefName(ref)
    case 'file-diff':
      return fileDiffRefName(ref)
    case 'snippet':
      return snippetRefName(ref)
    case 'repository':
      return repoRefName(ref)
    case 'symbol':
    case 'docset':
    case 'image':
    case 'thread-scoped-file':
      return ref.name
    case 'commit':
      return ref.message
    case 'pull-request':
      return ref.title
    case 'tree-comparison':
      return diffRefName(ref)
    case 'third-party':
      return ref.displayName
    case 'workspace-terminal-log':
      return 'terminal log'
    case 'text':
      return ref.name ? ref.name : 'text reference'
    case 'repo-instructions':
      return 'copilot-instructions.md'
    case 'issue':
      return ref?.title || ref.number.toString()
    case 'draft-issue':
      return ref.title
    case 'org-instructions':
      return ref?.owner
    case 'discussion':
      return ref?.title || ref.number.toString()
    case 'web-search-result':
      return ref.title
    case 'loading':
      return ref.title
    default:
      return 'unrecognized reference'
  }
}

export function referenceID(ref: CopilotChatReference): string {
  switch (ref.type) {
    case 'figma':
      return `${ref.type}-${ref.url}`
    case 'file':
      return `${ref.type}-${ref.repoOwner}/${ref.repoName}@${ref.commitOID}:${ref.path}`
    case 'folder':
      return `${ref.type}-${ref.repoOwner}/${ref.repoName}@${ref.ref}:${ref.path}`
    case 'file-changes':
      return `${ref.type}-${ref.repository.owner}/${ref.repository.owner}@${ref.ref}:${ref.path}`
    case 'file-diff':
      return `${ref.type}:${ref.baseFile?.path}@${ref.baseFile?.commitOID}-${ref.headFile?.path}@${ref.headFile?.commitOID}##${ref.selectedRange?.start}-${ref.selectedRange?.end}`
    case 'snippet':
      return `${ref.type}-${ref.repoOwner}/${ref.repoName}@${ref.commitOID}:${ref.path}#${ref.range.start}-${ref.range.end}`
    case 'repository':
      return `${ref.type}-${ref.id}-${ref.ownerLogin}/${ref.name}`
    case 'symbol':
      return `${ref.type}-${ref.kind}-${ref.name}` // TODO: attach repo?
    case 'docset':
      return `${ref.type}-${ref.name}` // TODO: repo too?
    case 'commit':
      return `${ref.type}-@${ref.oid}-${ref.repository.owner}/${ref.repository.name}`
    case 'pull-request':
      return `${ref.type}-${ref.id}-${ref.repository.ownerLogin}/${ref.repository.name}`
    case 'web-search':
      return `${ref.type}-${ref.query}`
    case 'web-search-result':
      return `${ref.type}-${ref.url}`
    case 'workspace-terminal-log':
      return `${ref.type}-${ref.repoOwner}/${ref.repoName}@${ref.pullRequestID}`
    case 'repo-instructions':
      return `${ref.type}-.github/custom-instructions.md`
    case 'image':
      return `${ref.type}-${ref.id}/${ref.name}`
    case 'issue':
      return `${ref.repository.owner}/${ref.repository.name}#${ref.number}`
    case 'draft-issue':
      return `${ref.type}-${ref.tag}`
    case 'text':
      return `${ref.type}-${ref.name}`
    case 'thread-scoped-file':
      return `${ref.type}-${ref.name}`
    case 'loading':
      return `${ref.type}-${ref.id}`
    default:
      return ''
  }
}

let renderableReferenceTypesCache: Set<CopilotChatReference['type']> | undefined = undefined

/**
 * Set of reference types that are able to be displayed to the user. All of these must be supported by `referenceName`
 * and `referenceId` have icons defined in ReferenceToken.
 */
export const renderableReferenceTypes = () =>
  // this is only a function because of the feature flag check, which is not allowed to be called at the module level
  (renderableReferenceTypesCache ??= new Set<CopilotChatReference['type']>([
    'commit',
    'discussion',
    'figma',
    'file',
    'file-v2',
    'file-diff',
    'folder',
    'issue',
    ...(copilotFeatureFlags.draftIssueUI ? ['draft-issue' as const] : []),
    'pull-request',
    'org-instructions',
    'repo-instructions',
    'snippet',
    'symbol',
    'third-party',
    'web-search',
    'web-search-result',
    'image',
    'thread-scoped-file',
    'loading',
    ...(copilotFeatureFlags.chatAutocomplete || copilotFeatureFlags.topicsAsReferences ? ['repository' as const] : []),
    ...(copilotFeatureFlags.topicsAsReferences ? (['docset'] as const) : []),
  ]))

export function getRenderableReferences(references: CopilotChatReference[]): CopilotChatReference[] {
  const newReferences = [] as CopilotChatReference[]

  for (const reference of references ?? []) {
    if (!renderableReferenceTypes().has(reference.type)) {
      continue
    }

    // The `bing-search` skill returns a single reference with multiple results.
    // Turn this into multiple references so we can properly render them.
    if (reference.type === 'web-search') {
      for (const webSearchResult of reference.results) {
        const webSearchResultReference = {...webSearchResult, type: 'web-search-result'} as WebSearchResultReference
        newReferences.push(webSearchResultReference)
      }

      continue
    }

    newReferences.push(reference)
  }

  return newReferences
}

function isMarkdown(reference: CopilotChatReference): boolean {
  if (reference.type !== 'file' && reference.type !== 'snippet') return false
  if (!reference.languageName) return false
  return reference.languageName.toLowerCase() === 'markdown'
}

function plainRenderableUrl(ref: SnippetReference): string {
  // Force .md files to render the code view so line ranges can be seen
  if (isMarkdown(ref)) {
    const url = new URL(ref.url, window.location.origin)
    url.search = 'plain=1'
    return url.href
  }

  return ref.url
}

export function referenceURL(ref: CopilotChatReference): string {
  switch (ref.type) {
    case 'repository':
      return `/${ref.ownerLogin}/${ref.name}`
    case 'commit':
      return ref.permalink
    case 'third-party':
      return ref.displayUrl
    case 'snippet':
      return plainRenderableUrl(ref)
    // TODO: handle symbol and docset URLs
    case 'issue':
    case 'figma':
    case 'file':
    case 'file-diff':
    case 'folder':
    case 'pull-request':
    case 'repo-instructions':
    case 'org-instructions':
    case 'web-search-result':
      return ref.url
    case 'symbol':
    case 'docset':
    case 'image':
    default:
      return '#'
  }
}

export function validReferenceURL(url: string): boolean {
  return url !== '#' && url !== ''
}

/**
 * Returns the folder of the reference.
 *
 * e.g. for "/foo/bar/file.ts" returns "foo/bar"
 */
export function referencePath(ref: FileReference | SnippetReference): string {
  const split = ref.path.split('/')
  split.pop()
  if (split.length === 0) {
    return '/'
  } else {
    return split.join('/')
  }
}

/**
 * Returns the file name of the reference.
 *
 * e.g. for "/foo/bar/file.ts" returns "file.ts"
 */
export function referenceFileName(ref: FileReference | FileChangesReference | SnippetReference): string {
  return fileRefName(ref)
}

function fileRefName(ref: FileReference | FileChangesReference | FolderReference | SnippetReference): string {
  const fileName = ref.path.split('/').pop()
  return fileName || ref.path
}

export function fileDiffRefName(ref: FileDiffReference): string {
  const path = ref.headFile?.path ?? ref.baseFile?.path
  const fileName = path?.split('/').pop() ?? ''

  // if we have no range or no start, just the filename
  if (!ref.selectedRange || !ref.selectedRange.start) {
    return fileName
  }

  // if we have no end or the end and start are the same, just the start line
  if (!ref.selectedRange.end || ref.selectedRange.start === ref.selectedRange.end) {
    return `${fileName} ${ref.selectedRange.start}`
  }

  // if we have a start and and end the range
  return `${fileName} ${ref.selectedRange.start}-${ref.selectedRange.end}`
}

function snippetRefName(ref: SnippetReference): string {
  if (ref.title) {
    return ref.title
  }
  const fileName = ref.path.split('/').pop()
  const lines = `${ref.range.start}-${ref.range.end}`
  return `${fileName}:${lines}`
}

function repoRefName(ref: RepositoryReference): string {
  return `${ref.ownerLogin}/${ref.name}`
}

function diffRefName(ref: TreeComparisonReference) {
  return `${ref.baseRevision.substring(0, 5)}..${ref.headRevision.substring(0, 5)}`
}

export function qualifyRef(ref: string, refType: 'branch' | 'tag'): string {
  if (refType === 'branch') return `refs/heads/${ref}`
  if (refType === 'tag') return `refs/tags/${ref}`
  return ref
}

export function parseReferencesFromLocation(location: Location, repo: CopilotChatRepo): CopilotChatReference[] {
  const refs: CopilotChatReference[] = []

  const blobMatch = location.pathname.match(/^\S+\/blob\/\w+\/(\S+)$/i)
  if (!blobMatch) return refs

  const fileRef: FileReference = {
    type: 'file',
    url: location.href,
    path: blobMatch.length > 1 ? blobMatch[1]! : blobMatch[0],
    repoID: repo.id,
    repoOwner: repo.ownerLogin,
    repoName: repo.name,
    ref: repo.ref,
    commitOID: repo.commitOID,
  }

  refs.push(fileRef)

  const lineSelection = parseBlobRange(location.hash)
  if (lineSelection) {
    const snippetRef: SnippetReference = {
      ...fileRef,
      type: 'snippet',
      range: {start: lineSelection.start.line, end: lineSelection.end.line},
    }

    refs.push(snippetRef)
  }

  return refs
}

// TODO: temporarily borrowing from github/blob-anchor.ts

interface BlobOffset {
  line: number
  column: number | null
}

interface BlobRange {
  start: BlobOffset
  end: BlobOffset
}

function parseBlobRange(str: string): BlobRange | undefined {
  const lines = str.match(/#?(?:L)(\d+)((?:C)(\d+))?/g)
  if (!lines) {
    return
  } else if (lines.length === 1) {
    const offset = parseBlobOffset(lines[0])
    if (!offset) return
    return Object.freeze({start: offset, end: offset})
  } else if (lines.length === 2) {
    const startOffset = parseBlobOffset(lines[0])
    const endOffset = parseBlobOffset(lines[1]!)
    if (!startOffset || !endOffset) return

    return ascendingBlobRange(
      Object.freeze({
        start: startOffset,
        end: endOffset,
      }),
    )
  } else {
    return
  }
}

function parseBlobOffset(str: string): BlobOffset | null {
  const lineMatch = str.match(/L(\d+)/)
  const columnMatch = str.match(/C(\d+)/)
  if (lineMatch) {
    return Object.freeze({
      line: parseInt(lineMatch[1]!),
      column: columnMatch ? parseInt(columnMatch[1]!) : null,
    })
  } else {
    return null
  }
}

function ascendingBlobRange(range: BlobRange): BlobRange {
  const offsets = [range.start, range.end]
  offsets.sort(compareBlobOffsets)

  if (offsets[0] === range.start && offsets[1] === range.end) {
    return range
  } else {
    return Object.freeze({
      start: offsets[0]!,
      end: offsets[1]!,
    })
  }
}

function compareBlobOffsets(a: BlobOffset, b: BlobOffset): number {
  if (a.line === b.line && a.column === b.column) {
    return 0
  } else if (a.line === b.line && typeof a.column === 'number' && typeof b.column === 'number') {
    return a.column - b.column
  } else {
    return a.line - b.line
  }
}

export function makeFileReference(file: string, repository: CopilotChatRepo): FileReference {
  const blobPath = repositoryTreePath({
    repo: repository,
    commitish: repository.refInfo.name,
    action: 'blob',
    path: file,
  })

  const fileRef: FileReference = {
    type: 'file',
    url: new URL(blobPath, window.location.origin).href,
    path: file,
    repoID: repository.id,
    repoOwner: repository.ownerLogin,
    repoName: repository.name,
    ref: repository.ref,
    commitOID: repository.commitOID,
  }

  return fileRef
}

export function makePlaceholderReference(file: File): LoadingReference {
  return {
    type: 'loading',
    title: file.name,
    id: crypto.randomUUID(),
    isClientOnly: true,
  }
}

export function makeFolderReference(path: string, repository: CopilotChatRepo): FolderReference {
  const treePath = repositoryTreePath({
    repo: repository,
    commitish: repository.refInfo.name,
    action: 'tree',
    path,
  })

  return {
    type: 'folder',
    url: new URL(treePath, window.location.origin).href,
    path,
    repoID: repository.id,
    repoOwner: repository.ownerLogin,
    repoName: repository.name,
    ref: repository.ref,
  }
}

export function getSymbolName(suggestion: BlackbirdSuggestion): string {
  return suggestion.symbol?.fully_qualified_name || ''
}

export function makeSymbolReference(
  suggestion: BlackbirdSuggestion,
  repository: CopilotChatRepo,
): SuggestionSymbolReference {
  const fullyQualifiedName: string = getSymbolName(suggestion)
  const symbolRef: CopilotChatReference = {
    type: 'symbol',
    kind: 'suggestionSymbol',
    name: fullyQualifiedName,
    suggestionDefinitions: [
      {
        identOffset: {start: suggestion.symbol?.ident_start || 0, end: suggestion.symbol?.ident_end || 0},
        extentOffset: {start: suggestion.symbol?.extent_start || 0, end: suggestion.symbol?.extent_end || 0},
        kind: suggestion.symbol?.kind || '',
        fullyQualifiedName,
        repoID: repository.id,
        repoOwner: repository.ownerLogin,
        repoName: repository.name,
        ref: suggestion.commit_sha,
        commitOID: suggestion.commit_sha,
        path: suggestion.path,
      },
    ],
    languageID: suggestion.language_id,
  }

  return symbolRef
}

/**
 * Making a docset reference from a docset is as simple as adding the 'docset' type
 * discriminator to the docset object. We don't have a good reason to limit the
 * fields in the object at runtime.
 */
export function makeDocsetReference(docset: Docset): DocsetReference {
  return {
    ...docset,
    type: 'docset',
  }
}

export function makeRepositoryReference(repo: CopilotChatRepo): RepositoryReference {
  return {...repo, type: 'repository'}
}

export function makeOrgInstructionsReference(owner: string): OrgInstructionsReference {
  return {
    owner: `${owner} Instructions`,
    type: 'org-instructions',
    url: 'https://docs.github.com/en/copilot/customizing-copilot/adding-organization-custom-instructions-for-github-copilot',
  }
}

export function isDocset(
  repoOrDocset: CopilotChatRepo | Docset | CopilotChatReference | undefined,
): repoOrDocset is Docset {
  return !!repoOrDocset && 'sourceRepos' in repoOrDocset
}

export function isRepository(repoOrDocset: CopilotChatRepo | Docset | undefined): repoOrDocset is CopilotChatRepo {
  return !!repoOrDocset && !isDocset(repoOrDocset)
}

export function getCustomInstructionsFromReferences(references: CopilotChatReference[]) {
  return references.reduce((list, ref) => {
    const repoRef = ref as RepositoryReference
    if ('customInstructions' in repoRef && Array.isArray(repoRef.customInstructions)) {
      list.push(...repoRef.customInstructions)
    }

    return list
  }, [] as CopilotCustomInstructions[])
}

export function hasCustomInstructions(repo: CopilotChatRepo | undefined, references: CopilotChatReference[]) {
  return copilotFeatureFlags.topicsAsReferences
    ? getCustomInstructionsFromReferences(references).length > 0
    : repo?.customInstructions && repo?.customInstructions?.length > 0
}

export function referencesAreEqual(a: CopilotChatReference | undefined, b: CopilotChatReference | undefined): boolean {
  // if both are undefined, they're equal
  if (a === b) {
    return true
  }

  // if either is undefined now, they are not equal
  if (a === undefined || b === undefined) {
    return false
  }

  return referenceID(a) === referenceID(b)
}

export function referenceArraysAreEqual(
  a: CopilotChatReference[] | undefined,
  b: CopilotChatReference[] | undefined,
): boolean {
  if (a === undefined && b === undefined) return true
  if (a === undefined || b === undefined) return false

  if (a.length !== b.length) {
    return false
  }

  for (let i = 0; i < a.length; i++) {
    if (!referencesAreEqual(a[i], b[i])) {
      return false
    }
  }

  return true
}

export function navigateToAllTopics(showTopicPicker: (show: boolean) => void, mode: CopilotChatMode) {
  showTopicPicker(true)
  if (mode === 'immersive') {
    addUrlToHistoryStack(`${COPILOT_PATH}`)
  }
}

export function isFileReference(reference: CopilotChatReference): reference is FileReference {
  return reference.type === 'file'
}

export function isSnippetReference(reference: CopilotChatReference): reference is SnippetReference {
  return reference.type === 'snippet'
}

export function isImageReference(reference: CopilotChatReference): reference is ImageReference {
  return reference.type === 'image'
}

export function isIssueReference(reference: CopilotChatReference): reference is IssueReference {
  return reference.type === 'issue'
}

export function isPullRequestReference(reference: CopilotChatReference): reference is PullRequestReference {
  return reference.type === 'pull-request'
}

type Author = {
  name: string
  avatarURL: string
  type: 'user' | 'copilot' | 'agent'
}

/**
 * Returns the author of a message.
 */
export function findAuthor(message: CopilotChatMessage, currentUserLogin: string): Author {
  if (message.role === 'user') {
    return {
      name: currentUserLogin,
      avatarURL: `/${currentUserLogin}.png`,
      type: 'user',
    }
  }

  if (message.references) {
    const agentReference = message.references.find(ref => ref.type === 'github.agent') as GitHubAgentReference | null
    if (agentReference) {
      return {
        name: agentReference.login,
        avatarURL: agentReference.avatarURL,
        type: 'agent',
      }
    }
  }

  return {
    name: 'Copilot',
    avatarURL: '',
    type: 'copilot',
  }
}

export function isAgent(author: Author): boolean {
  return author.type === 'agent'
}

/**
 * Finds all the agents who have sent messages to the thread.
 */
export function findAgentCorrespondents(messages: readonly CopilotChatMessage[]): Author[] {
  const agentMessages = messages.map(message => findAuthor(message, '')).filter(author => author?.type === 'agent')
  const uniqueAgents = new Map<string, Author>()
  for (const agent of agentMessages) {
    uniqueAgents.set(agent.name, agent)
  }
  return Array.from(uniqueAgents.values())
}

export function isThreadOlderThan4Hours(thread: CopilotChatThread) {
  const threadUpdatedAt = new Date(thread.updatedAt).getTime()
  const now = Date.now()
  const timeSinceLastMessage = now - threadUpdatedAt
  const fourHours = 4 * 60 * 60 * 1000

  return timeSinceLastMessage > fourHours
}

export function filterUniqueConfirmations(
  confirmations: CopilotAgentConfirmation[] | null | undefined,
): CopilotAgentConfirmation[] {
  if (!confirmations) return []
  const set = new Set<string>()
  return confirmations.filter(confirmation => {
    const key = JSON.stringify(confirmation.confirmation)
    if (set.has(key)) {
      return false
    }
    set.add(key)
    return true
  })
}

export function getThreadStaticSuggestions(
  context: CopilotChatReference | CopilotChatRepo | Docset,
): CopilotChatSuggestions {
  // NOTE: some reference types have a suffix that we still want to match
  const referenceType = 'type' in context && typeof context.type === 'string' ? context.type : 'repository'
  const normalizedType = referenceType ? referenceType.replace(/(\.api|-v2)$/, '').toLowerCase() : 'default'
  const maxNumOfSuggestions = 3

  if (isFeatureEnabled('copilot_task_oriented_assistive_prompts')) {
    const contextPersona = 'persona' in context && typeof context.persona === 'string' ? context.persona : undefined
    const contextCommandSuggestions = getCommandSuggestions(normalizedType, contextPersona)
    const globalCommandSuggestions = getCommandSuggestions('global')

    // Order of precedence
    // 1. Context-specific, task-oriented commands
    // 2. Context-specific, open-ended suggestions
    // 3. Global/Default, task-oriented commands
    let suggestions = contextCommandSuggestions.length ? contextCommandSuggestions : threadSuggestions[normalizedType]
    if (!suggestions) {
      // Append default suggestions when there are smaller number of global commands than maxNumOfSuggestions
      suggestions = [
        ...globalCommandSuggestions,
        ...(globalCommandSuggestions.length < maxNumOfSuggestions
          ? shuffle(threadSuggestions.default!).slice(0, maxNumOfSuggestions - globalCommandSuggestions.length)
          : []),
      ]
    }

    const shuffledSuggestions = shuffle(suggestions)
    return {
      referenceType,
      suggestions: shuffledSuggestions.slice(0, maxNumOfSuggestions),
    }
  } else {
    const suggestions = threadSuggestions[normalizedType] || threadSuggestions.default
    const shuffledSuggestions = shuffle(suggestions!)
    return {
      referenceType,
      suggestions: shuffledSuggestions.slice(0, maxNumOfSuggestions),
    }
  }
}

export function shuffle<T>(list: T[]): T[] {
  const shuffled = list.slice() // make a copy of the original array
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1)) // choose a random index between 0 and i
    const temp = shuffled[i]!
    shuffled[i] = shuffled[j]!
    shuffled[j] = temp
  }
  return shuffled
}

export function srOnlyHeader(author: string, message: string) {
  const messageArr = message.split(' ')
  let prefix = `${author} said`
  if (author === 'Timeline') {
    prefix = 'The following action was initiated'
  }
  return `${prefix}: ${messageArr.slice(0, messageArr.length < 7 ? messageArr.length : 7).join(' ')}`
}
