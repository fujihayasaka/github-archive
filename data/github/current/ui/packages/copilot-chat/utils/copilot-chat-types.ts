import type {CustomCopilotResource} from '@github-ui/custom-copilots/types'
import type {SafeHTMLString} from '@github-ui/safe-html'

import type {DotcomFileAttachment} from './uploadable-file-attachment'

export type TopicItem = {
  databaseId: number
  isInOrganization: boolean
  name: string
  nwo: string
  ownerLogin: string
  ownerAvatarUrl: string
}

export type CopilotChatRepo = {
  id: number
  name: string
  ownerLogin: string
  ownerType: 'User' | 'Organization'
  readmePath?: string
  description?: string
  commitOID: string
  ref: string
  refInfo: {
    name: string
    type: 'branch' | 'tag' | 'tree'
  }
  visibility: string
  languages?: Array<{name: string; percent: number}>
  customInstructions?: CopilotCustomInstructions[]
  path?: string
}

export type CopilotCustomInstructions = {
  type: 'Organization' | 'Repository' | 'Assistant'
  prompt: string
  owner: string
}

export type CopilotChatPlan = Record<string, never>

export type CopilotChatOrg = {
  id: string
  login: string
  avatarUrl: string
}

export type CopilotChatThread = {
  id: string
  name: string
  repoID?: number
  currentReferences?: CopilotChatReference[]
  createdAt: string
  updatedAt: string
  sharedID?: string
  sharedAt?: string
  sharedMessageID?: string
  customCopilotID?: number
  customCopilotOwner?: string
}

export type CopilotChatDuplicate = {
  thread: CopilotChatThread
  messages: CopilotChatMessage[]
}

export type CopilotChatSuggestions = {
  referenceType?: string
  suggestions: GeneratedSuggestion[]
}

export type GeneratedSuggestion = {
  question: string
  intent?: CopilotChatIntentsType
  mode?: CopilotChatMode
  prompt?: string
}

export type SkillExecution = {
  slug: string
  status: FunctionCalledStatus
  arguments?: string
  errorMessage?: string
  references?: CopilotChatReference[]
  statusMessage?: string
}

export type CopilotChatAgent = {
  name: string
  slug: string
  avatarUrl: string
  integrationUrl: string
}

export type CustomCopilot = {
  name: string
  slug: string
  /** The login of the owner */
  owner?: string
  /** The number if the owner is present, or the id */
  id: number
  /**
   * The oldId field lets us find threads that use the old id format
   */
  oldId: number
  updatedAt: string
  slugWithOwner: string
  description: string | null
  sizePercentage: number
  resources: CustomCopilotResource[]
  generalInstructions: string | null
  iconType?: string
  iconColor?: string
  ownerIsOrg: boolean
  ownerAvatar: string
  /**
   * If the user has a display name set on their profile, we use that here.
   * Otherwise, we use their login
   */
  ownerDisplayName: string
  visibility: CustomCopilotVisibility
  editable: boolean
  starred: boolean
  starredUsers: CustomCopilotStarredUser[]
}

export type CustomCopilotStarredUser = {
  login: string
  avatarUrl: string
}

export type IndexCustomCopilot = Pick<
  CustomCopilot,
  | 'id'
  | 'oldId'
  | 'name'
  | 'owner'
  | 'updatedAt'
  | 'description'
  | 'iconType'
  | 'iconColor'
  | 'ownerIsOrg'
  | 'ownerAvatar'
  | 'ownerDisplayName'
  | 'visibility'
  | 'editable'
  | 'starred'
>

export type CustomCopilotId = Pick<CustomCopilot, 'id' | 'owner'>

export type CustomCopilotVisibility = 'private' | 'org_public'

export type CustomCopilotPayload = CustomCopilot | {protectedOrganizations: string[]}

export type CopilotChatMessage = {
  id: string
  requestID?: string
  intent?: string
  role: 'user' | 'assistant'
  model?: string
  content?: string
  createdAt: string
  threadID: string
  parentMessageID?: string
  error?: ChatError
  references: CopilotChatReference[] | null
  skillExecutions?: SkillExecution[]
  copilotAnnotations?: CopilotAnnotations
  interrupted?: boolean
  confirmations?: CopilotAgentConfirmation[] | null // confirmation from copilot/agent
  clientConfirmations?: CopilotClientConfirmation[] | null // users response to agent confirmation
  clientSkillsRequests?: ToolCallRequest[]
  clientToolResults?: ToolCallResult[]
  agentErrors?: CopilotAgentError[]
  feedback?: CopilotChatMessageFeedback
  mediaContent?: MediaContentItem[]
  clientSide?: boolean // The message only exists on client side initially
  // Subthreading properties:
  messageIndex?: number // the index of this message in the messages array
  parentMessageIndex?: number // the index of the parent message in the messages array
  childMessageIndexes?: number[] // the indexes of this message's children in the messages array
  selectedChildIndex?: number // the index of the child that's visible in the messages array
  skillOptions?: SkillOptions
}

export type SkillOptions = {
  deepCodeSearch: boolean
}

export type MediaContentItem = {
  mediaType: string
  name: string
  url: string
  chatAttachmentUrl?: string
  height?: number
  width?: number
}

export type CopilotAgentConfirmation = {
  title: string
  message: string
  confirmation: object
  onSubmit?: (accepted: boolean) => void
}

export type Invocation = {
  name: string
  arguments: string
}

export type CopilotAgentError = {
  type: string
  code: string
  message: string
  identifier: string
}

export type CopilotClientConfirmation = {
  state: CopilotClientConfirmationState
  confirmation: object
}

export type CopilotClientConfirmationState = 'accepted' | 'dismissed'

export type CopilotChatMessageFeedback = 'POSITIVE' | 'NEGATIVE'

export type CopilotAnnotations = {
  CodeVulnerability?: Array<Annotation<CodeVulnerability>> | null
  PublicCodeReference?: Array<Annotation<PublicCodeReference>> | null
}

export type Annotation<T> = {
  startOffset: number
  endOffset: number
  details: T
}

export type CodeVulnerability = {
  type: string
  uiType: string
  description: string
  uiDescription: string
}

export type PublicCodeReference = {
  sourceURL: string
  license: string
  language: string
}

export type RepositoryReference = CopilotChatRepo & {
  type: 'repository'
}

export interface ReferenceHeaderInfo {
  blobSize: string
  displayName: string
  isLfs: boolean
  lineInfo: {truncatedLoc: number; truncatedSloc: number}
  rawBlobUrl: string
  viewable: boolean
}

type APIResponseResource =
  | {resourceType: 'Repository'; data: Omit<RepositoryAPIReference, 'type'>}
  | {resourceType: 'Issue'; data: Omit<IssueAPIReference, 'type'>}
  | {resourceType: 'Release'; data: Omit<ReleaseAPIReference, 'type'>}
  | {resourceType: 'PullRequest'; data: Omit<PullRequestAPIReference, 'type'>}
  | {resourceType: 'Commit'; data: Omit<CommitAPIReference, 'type'>}
  | {resourceType: 'Topic'; data: Omit<TopicAPIReference, 'type'>}

export type APIResponseReference = APIResponseResource & {
  type: 'api-response'
  id: number
  repo?: string
}

export type RepoInstructionsReference = {
  type: 'repo-instructions'
  url: string
}

export type OrgInstructionsReference = {
  type: 'org-instructions'
  owner: string
  url: string
}

export type LoopReference = {
  type: 'pipe' | 'loop'
  id: string
  title: string
  description?: string
  nodes: LoopNode[]
}

export type LoopNode = {
  id: string
  title: string
  description: string
  type: string
  inputType?: {
    type: string
    min?: number
    max?: number
    options?: string[]
  }
  content?: string
  model?: string
}

export type FolderReference = {
  type: 'folder'
  url: string
  path: string
  repoID: number
  repoOwner: string
  repoName: string
  ref: string
}

export type FileReference = {
  type: 'file' | 'file-v2'
  url: string
  path: string
  repoID: number
  repoOwner: string
  repoName: string
  ref: string
  commitOID: string
  languageName?: string
  languageId?: number
  refOrigin?: 'custom_copilot' | ''
}

export type FigmaReference = {
  type: 'figma'
  title: string
  url: string
  id: string
  thumbnailUrl: string
  fullImageUrl: string
  authenticationRequired?: true
}

export type ImageReference = {
  file?: File // file is used to indicate that we have a file that needs to be processed, usually to a url
  id: string
  attachment: DotcomFileAttachment
  type: 'image'
  mediaType?: string
  imageUrl?: string // currently only supports base64 dataUrls. If this is null, the file hasn't finished loading.
  name: string
}

export type FileChangesReference = {
  type: 'file-changes'
  ref: string
  path: string
  url: string
  commits: Array<{
    oid: string
    shortSha: string
    message: string
    createdAt: string
    author: {
      name: string
      email: string
      login: string
    }
    blameLines: Array<{
      lineNo: number
      text: string
    }>
  }>
  repository: {
    id: number
    name: string
    owner: string
  }
}

export interface FileReferenceDetails extends FileReference {
  contents: string
  highlightedContents: SafeHTMLString[]
  repoIsOrgOwned: boolean
  range: LineRange
  expandedRange: LineRange
  headerInfo: ReferenceHeaderInfo
}

export interface FileDiffReference {
  type: 'file-diff'
  id: string
  url: string
  baseFile: FileReference | null // will be null if a file was 'added'
  headFile: FileReference | null // will be null if a file was 'removed'
  baseBranchRef: string | undefined
  // user-selected, shown in location.hash, ex L1-R5
  // won't be populated in the server props but should be present when calling CAPI
  selectedRange?: {
    start?: string
    end?: string
  }
}

export interface FileDiffReferenceDetails extends FileDiffReference {
  contents: string
  highlightedContents: SafeHTMLString[]
  repoIsOrgOwned: boolean
  expandedRange: LineRange
}

export interface TerminalLogReference {
  type: 'workspace-terminal-log'
  output: string
  pullRequestID: string
  repoID: number
  repoOwner: string
  repoName: string
}

export interface SnippetReference {
  type: 'snippet'
  url: string
  path: string
  repoID: number
  repoOwner: string
  repoName: string
  ref: string
  commitOID: string
  range: LineRange
  languageID?: number
  languageName?: string
  title?: string
}

export interface SnippetReferenceDetails extends SnippetReference {
  contents: string
  highlightedContents: SafeHTMLString[]
  repoIsOrgOwned: boolean
  expandedRange: LineRange
  headerInfo: ReferenceHeaderInfo
}

export interface CommitReference {
  type: 'commit'
  oid: string
  message: string
  permalink: string
  author: {
    name: string
    email: string
    login: string
  }
  repository: {
    id: number
    name: string
    owner: string
  }
}

export interface PullRequestReference {
  type: 'pull-request'
  title: string
  id: number
  number: number
  url: string
  commit?: string
  state?: string
  draft?: boolean
  authorLogin: string
  repository: CopilotChatRepo
}

export const TREE_COMPARISON_REFERENCE_TYPE = 'tree-comparison'
export interface TreeComparisonReference {
  type: typeof TREE_COMPARISON_REFERENCE_TYPE
  baseRepoId: number
  headRepoId: number
  baseRevision: string
  headRevision: string
  diffHunks: DiffHunkReference[]
}

export interface DiffHunkReference {
  type: 'diff-hunk'
  changeReference: string
  diff: string
  fileName: string
  headerContext: string
}

export interface IssueReference {
  type: 'issue'
  id: number
  number: number
  repository: {
    id: number
    name: string
    owner: string
  }
  title?: string
  body?: string
  state?: string
  authorLogin?: string
  url: string
  assignees?: string[]
  pullRequestUrl?: string
}

export interface DiscussionReference {
  type: 'discussion'
  number: number
  title: string
  body: string
  user: {
    login: string
  }
  state: string
  id: number
  url: string
  authorLogin: string
  repository: {
    id: number
    name: string
    owner: string
  }
}

export interface ReleaseReference {
  type: 'release'
  name?: string
  tagName?: string
  url?: string
  repository: {
    id: number
    name: string
    owner: string
  }
  body?: string
  isDraft: boolean
  isPrerelease: boolean
  authorLogin?: string
  targetCommitish?: string
}

export interface ReleaseAPIReference {
  type: 'release.api'
  name?: string
  tag_name: string
  html_url?: string
}

export interface PullRequestAPIReference {
  type: 'pull-request.api'
  title?: string
  html_url?: string
  number: number
  repo?: string
}

export interface AlertReference {
  type: 'alert.api'
  number: number
  repo?: string
}

export interface IssueAPIReference {
  type: 'issue.api'
  title?: string
  html_url: string
  number: number
  repo?: string
  state: string
}

export interface RepositoryAPIReference {
  type: 'repository.api'
  name: string
  description?: string
  html_url?: string
}

export interface CommitAPIReference {
  type: 'commit.api'
  sha: string
  commit: {
    message?: string
  }
  html_url?: string
}

export interface DiffAPIReference {
  type: 'diff.api'
}

export interface FileAPIReference {
  type: 'file.api'
}

export interface TopicAPIReference {
  type: 'topic.api'
  name: string
  display_name?: string
  short_description?: string
}

export interface TextReference {
  type: 'text'
  name?: string
  text?: string
}

export interface ThreadScopedFileReference {
  type: 'thread-scoped-file'
  name: string
  text: string
  language: string
}

// Represents a user-edited draft issue from the "create issue" flow in Copilot chat.
export interface DraftIssueReference {
  type: 'draft-issue'
  tag: string
  parentTag: string | undefined
  title: string
  description: string | undefined
  repository: string | undefined
  template: string | undefined
  assignees: string[] | undefined
  labels: string[] | undefined
  issueType: string | undefined
  projects: string[] | undefined
  milestone: string | undefined
}

export interface ThirdPartyReference {
  type: 'third-party'
  displayName: string
  displayUrl: string
  displayIcon: string
  data: string
  thirdPartyType?: string
}

export type ToolCallRequest = {
  id: string
  type: 'function'
  function: {
    name: string
    arguments: string
  }
}

export interface UnsupportedAPIReference {
  type: 'unsupported'
  text?: string
}

export interface LineRange {
  start: number
  end: number
}

export interface CodeNavSymbolReference {
  type: 'symbol'
  kind: 'codeNavSymbol'
  name: string
  languageID?: number
  codeNavDefinitions?: CodeNavSymbol[]
  codeNavReferences?: CodeReference[]
  languageName?: string
}

export interface CodeNavSymbolReferenceDetails extends CodeNavSymbolReference {
  codeNavDefinitions?: CodeNavSymbolDetails[]
  codeNavReferences?: CodeReferenceDetails[]
}

export interface SuggestionSymbolReference {
  type: 'symbol'
  kind: 'suggestionSymbol'
  name: string
  languageID?: number
  suggestionDefinitions?: SuggestionSymbol[]
}

export interface SuggestionSymbolReferenceDetails extends SuggestionSymbolReference {
  suggestionDefinitions?: SuggestionSymbolDetails[]
}

export type DocsetReference = {
  type: 'docset'
  name: string
  id: string
  avatarUrl: string
  // Docset references coming from previous threads in CAPI currently don't have their
  // repos serialized.
  repos?: string[]
  description: string
}

export type MagicKbReference = {
  type: 'magic-knowledge-base'
}

export type GitHubAgentReference = {
  type: 'github.agent'
  login: string
  avatarURL: string
}

export type WebSearchResultReference = {
  type: 'web-search-result'
  reference_type?: string
  title: string
  excerpt: string
  url: string
}

export type WebSearchReference = {
  type: 'web-search'
  query: string
  results: WebSearchResultReference[]
  status: string
  agent_response: AgentResponse
}

export type AgentResponse = {
  type: string
  text: AgentResponseText
  bing_searches: BingSearch[]
}

type AgentResponseText = {
  value: string
  annotations: AgentAnnotation[]
}

type AgentAnnotation = {
  type: string
  text: string
  start_index: number
  end_index: number
  url_citation: UrlCitation
}

type UrlCitation = {
  url: string
  title: string
}

type BingSearch = {
  text: string
  url: string
}

export type SupportDocumentReference = {
  type: 'support-document'
  query: string
  results: Array<{title: string; content: string; url: string}>
  status: string
}

export type JobReference = {
  type: 'job'
  id: string
  repoId: number
  repoName: string
  repoOwner: string
}

export type PlanReference = {
  type: 'plan'
}

type CodeNavSymbol = {
  ident: Range
  extent: Range
} & CodeSymbol

type SuggestionSymbol = {
  identOffset?: ByteOffset
  extentOffset?: ByteOffset
} & CodeSymbol

type CodeSymbol = {
  kind: string
  fullyQualifiedName: string
  repoID: number
  repoOwner: string
  repoName: string
  ref: string
  commitOID: string
  path: string
}

type CodeReference = {
  ident: Range
  repoID: number
  repoOwner: string
  repoName: string
  ref: string
  commitOID: string
  path: string
}

type SymbolDetails = {
  repoIsOrgOwned: boolean
  highlightedContents?: SafeHTMLString[]
  range?: LineRange
}

export type CodeNavSymbolDetails = CodeNavSymbol & SymbolDetails
export type SuggestionSymbolDetails = SuggestionSymbol & SymbolDetails
export type CodeReferenceDetails = CodeReference & SymbolDetails

type Range = {
  start: Position
  end: Position
}

type Position = {
  line: number
  column: number
}

type ByteOffset = {
  start: number
  end: number
}

/** This is a fake placeholder reference type that only exists on the client. It will not be sent to CAPI. */
export interface LoadingReference {
  type: 'loading'
  isClientOnly: true
  title: string
  id: string
}

export type CopilotChatReference =
  | FileReference
  | FolderReference
  | FileChangesReference
  | SnippetReference
  | FileDiffReference
  | RepositoryReference
  | CodeNavSymbolReference
  | SuggestionSymbolReference
  | DocsetReference
  | CommitReference
  | PullRequestReference
  | GitHubAgentReference
  | WebSearchReference
  | WebSearchResultReference
  | TreeComparisonReference
  | IssueReference
  | TextReference
  | ReleaseReference
  | DiscussionReference
  | JobReference
  | PlanReference
  | ReleaseAPIReference
  | PullRequestAPIReference
  | AlertReference
  | IssueAPIReference
  | RepositoryAPIReference
  | CommitAPIReference
  | DiffAPIReference
  | FileAPIReference
  | TopicAPIReference
  | APIResponseReference
  | UnsupportedAPIReference
  | ThirdPartyReference
  | TerminalLogReference
  | MagicKbReference
  | DiffHunkReference
  | RepoInstructionsReference
  | ImageReference
  | ThreadScopedFileReference
  | DraftIssueReference
  | FigmaReference
  | OrgInstructionsReference
  | LoopReference
  | LoadingReference

export type CopilotChatReferenceType = CopilotChatReference['type']

export type CopilotChatReferenceDetails = SnippetReferenceDetails

export type ReferenceDetails<TReference extends CopilotChatReference> = TReference extends SnippetReference
  ? SnippetReferenceDetails
  : TReference extends FileReference
    ? FileReferenceDetails
    : TReference extends CodeNavSymbolReference
      ? CodeNavSymbolReferenceDetails
      : TReference extends SuggestionSymbolReference
        ? SuggestionSymbolReferenceDetails
        : TReference extends FileDiffReference
          ? FileDiffReferenceDetails
          : unknown

type CopilotChatExplainEventPayload = {
  intent: typeof CopilotChatIntents.explain
  content: string
  references: CopilotChatReference[]
  id?: string
}

type CopilotChatAskEventPayload = {
  intent: typeof CopilotChatIntents.conversation
  references?: CopilotChatReference[]
  id?: string
}

type CopilotChatAskPrEventPayload = {
  intent: typeof CopilotChatIntents.conversation
  references: CopilotChatReference[]
  id?: string
}

type CopilotChatExplainPrEventPayload = {
  intent: typeof CopilotChatIntents.explainFileDiff
  content: string
  references: CopilotChatReference[]
  id?: string
}

type CopilotChatSuggestEventPayload = {
  intent: typeof CopilotChatIntents.suggest
  content: string
  references: CopilotChatReference[]
  id?: string
}

type CopilotChatReviewPrEventPayload = {
  intent: typeof CopilotChatIntents.reviewPr
  content: string
  references: CopilotChatReference[]
  completion: string
  thread: CopilotChatThread
  id?: string
}

type CopilotChatStartConversationPayload = {
  intent: typeof CopilotChatIntents.conversation
  content: string
  references: CopilotChatReference[]
  id?: string
}

type CopilotChatStartConversationNewThreadPayload = {
  intent: typeof CopilotChatIntents.conversation
  references: CopilotChatReference[]
  newThread: boolean
  id?: string
}

type CopilotChatStartAttachedConversationPayload = {
  intent: typeof CopilotChatIntents.conversation
  references: CopilotChatReference[]
  attachThread: boolean
  id?: string
}

type ActionsAgentPayload = {
  intent: typeof CopilotChatIntents.actionsAgent
  content: string
  references: CopilotChatReference[]
  id?: string
}

export type CopilotChatEventPayload =
  | CopilotChatExplainEventPayload
  | CopilotChatAskEventPayload
  | CopilotChatSuggestEventPayload
  | CopilotChatAskPrEventPayload
  | CopilotChatExplainPrEventPayload
  | CopilotChatReviewPrEventPayload
  | CopilotChatStartConversationPayload
  | CopilotChatStartConversationNewThreadPayload
  | CopilotChatStartAttachedConversationPayload
  | ActionsAgentPayload

export const CopilotChatIntents = {
  explain: 'explain',
  conversation: 'conversation',
  suggest: 'suggest',
  discussFileDiff: 'discuss-file-diff',
  explainFileDiff: 'explain-file-diff',
  reviewPr: 'review-pull-request',
  actionsAgent: 'actions-agent',
} as const
export type CopilotChatIntentsType = (typeof CopilotChatIntents)[keyof typeof CopilotChatIntents]

interface ChatErrorBase {
  type: MessageStreamingErrorType | 'basic'
  isError: boolean
  message?: React.ReactNode
  details?: unknown
  retryable?: boolean
}

interface BasicChatError extends ChatErrorBase {
  type: 'basic'
  isError: true
}

interface FilteredChatError extends ChatErrorBase {
  type: 'filtered'
  isError: true
}

interface PublicCodeChatError extends ChatErrorBase {
  type: 'publicCode'
  isError: true
}

interface AgentError<TType extends MessageStreamingErrorType, TDetails> extends ChatErrorBase {
  type: TType
  isError: true
  details: TDetails
}

export type AgentUnauthorizedChatError = AgentError<'agentUnauthorized', NotAuthorizedForAgentErrorPayload>
export type AgentRequestChatError = AgentError<'agentRequest', AppAgentRequestErrorPayload>
export type AgentChatError = AgentUnauthorizedChatError | AgentRequestChatError

export type ChatError = BasicChatError | AgentChatError | FilteredChatError | PublicCodeChatError

export type BlackbirdSymbol = {
  fully_qualified_name: string
  kind: string
  ident_start: number
  ident_end: number
  extent_start: number
  extent_end: number
}

export interface BlackbirdSuggestion {
  kind: string
  query: string
  repository_nwo: string
  language_id: number
  path: string
  repository_id: number
  commit_sha: string
  line_number: number
  symbol: BlackbirdSymbol | null
}

export interface RepoFilesResult {
  paths?: string[]
  directories?: string[]
}

export type SuggestionsResponse = {
  suggestions: BlackbirdSuggestion[]
  queryErrors: string[]
  failed: boolean
}

export type KnowledgeBasesResponse = {
  knowledgeBases: Docset[]
  administratedCopilotEnterpriseOrganizations: CopilotChatOrg[] | null
}

export interface Docset {
  id: string
  name: string
  description: string
  createdByID: number
  ownerID: number
  ownerLogin: string
  ownerType: string
  visibility: string
  repos: string[]
  sourceRepos?: SourceRepo[]
  visibleOutsideOrg: boolean
  iconHtml?: SafeHTMLString
  avatarUrl: string
  adminableByUser: boolean
  /**
   * Orgs which own at least one repo in the docset but that the current user is not currently SSO'd into
   */
  protectedOrganizations: string[]
  canChat?: boolean
}

export interface RepoData {
  databaseId: number | null | undefined
  name: string
  nameWithOwner: string
  isInOrganization: boolean
  shortDescriptionHTML: string
  paths?: string[]
  owner: {
    databaseId: number | null | undefined
    avatarUrl: string
    login: string
  }
}

export interface DocsetRepo extends RepoData {
  paths: string[]
}

export interface SourceRepo {
  id: number
  ownerID: number
  paths: string[]
}

export type MessageStreamingResponse =
  | MessageStreamingResponseContent
  | MessageStreamingResponseError
  | MessageStreamingResponseComplete
  | MessageStreamingResponseDebug
  | MessageStreamingResponseFunctionCall
  | MessageStreamingResponseClientSkillsRequest
  | MessageStreamingResponseConfirmation
  | MessageStreamingResponseAgentError
  | MessageStreamingResponseDroppedComponents
  | MessageStreamingResponseThreadTitle

export type MessageStreamingResponseContent = {
  type: 'content'
  body: string
}

export type MessageStreamingResponseDebug = {
  type: 'debug'
  body: string
}

export const MESSAGE_STREAMING_ERROR_TYPES = [
  'exception',
  'filtered',
  'publicCode',
  'contentTooLarge',
  'rateLimit',
  'agentUnauthorized',
  'agentRequest',
  'networkError',
  'multipleAgentsAttempt',
] as const

type MessageStreamingErrorTypes = typeof MESSAGE_STREAMING_ERROR_TYPES
export type MessageStreamingErrorType = MessageStreamingErrorTypes[number]

export type MessageStreamingResponseError = {
  type: 'error'
  errorType: MessageStreamingErrorType
  description: string
}

export type MessageStreamingResponseComplete = {
  type: 'complete'
  id: string
  turnId: string
  createdAt: string
  intent: string
  references: CopilotChatReference[] | null
  copilotAnnotations?: CopilotAnnotations
  parentMessageID?: string
  model: string
  role: string
}

export type MessageStreamingResponseFunctionCall = {
  arguments: string
  type: 'functionCall'
  name: string
  status: FunctionCalledStatus
  errorMessage: string
  references: CopilotChatReference[]
  statusMessage: string
}

export type MessageStreamingResponseClientSkillsRequest = {
  type: 'clientSkillsRequest'
  toolCalls: ToolCallRequest[]
}

export type MessageStreamingResponseConfirmation = {
  type: 'confirmation'
  title: string
  message: string
  confirmation: object
}

export type MessageStreamingResponseAgentError = {
  type: 'agentError'
  agentErrorType: string
  code: string
  message: string
  identifier: string
}

export type MessageStreamingResponseDroppedComponents = {
  type: 'droppedComponent'
  hasDroppedComponents: boolean
}

export type MessageStreamingResponseThreadTitle = {
  type: 'threadTitle'
  title: string
}

export type FunctionArguments =
  | BingSearchArguments
  | SemanticSearchArguments
  | LexicalSearchArguments
  | CreateIssueArguments
  | GetAlertArguments
  | JobLogsArguments
  | KnowledgeBaseSearchArguments
  | GetFileArguments
  | GetFileChangesArguments
  | GetDiscussionArguments
  | PlanArguments
  | GitHubAPIArguments
  | SupportSearchArguments
  | GetFigmaArguments
  | CodeSearchAgentSkillArguments

export type BingSearchArguments = {kind: 'bing-search'; query: string; freshness?: string}
export type SupportSearchArguments = {kind: 'support-search'; rawUserQuery: string}
export type SemanticSearchArguments = {kind: 'semantic-code-search'; query: string; repoName: string; repoOwner: string}
export type LexicalSearchArguments = {kind: 'lexical-code-search'; query: string; scopingQuery: string}
export type KnowledgeBaseSearchArguments = {kind: 'kb-search'; query: string; kbID: string}
export type GetFileArguments = {kind: 'getfile'; repo: string; path: string; ref?: string}
export type GetFileChangesArguments = {kind: 'getfilechanges'; repo: string; path: string; ref: string; max?: number}
export type CreateIssueArguments = {
  kind: 'githubissuecreate'
  repo: string
  assignees: string[]
  labels: string[]
  title: string
  body: string
}
export type GetAlertArguments = {kind: 'getalert'; url: string}
export type JobLogsArguments = {
  kind: 'get-actions-job-logs'
  repo: string
  jobId?: number
  pullRequestNumber?: number
  runId?: number
  workflowPath?: string
}
export type GetDiscussionArguments = {kind: 'getdiscussion'; repo: string; discussionNumber: number; owner: string}
export type PlanArguments = {kind: 'planskill'; user_query: string}
export type GitHubAPIArguments = {
  kind: 'get-github-data'
  endpoint: string
  repo: string
  endpointDescription?: string
  task?: string
}
export type GetFigmaArguments = {
  kind: 'get-figma'
  name: string
}
export type CodeSearchAgentSkillArguments = {
  kind: 'codesearchagentskill'
  userQuery: string
  repoOwner: string
  repoName: string
}

export const SUPPORTED_FUNCTIONS = [
  'bing-search',
  'codesearch',
  'semantic-code-search',
  'lexical-code-search',
  'kb-search',
  'getfile',
  'getfilechanges',
  'getdiscussion',
  'get-actions-job-logs',
  'getalert',
  'planskill',
  'get-github-data',
  'support-search',
  'get-figma',
  'codesearchagentskill',
]

export type FunctionCalledStatus = 'completed' | 'started' | 'error' | 'unsupported' | 'progress'

export type NotAuthorizedForAgentErrorPayload = {
  authorize_url: string
  client_id: string
  name: string
  avatar_url: string
  slug: string
  description: string
}

export type AppAgentRequestErrorPayload = {
  type: string
  code: string
  identifier: string
  message: string
}

export type CopilotChatMode = 'immersive' | 'assistive' | 'task-oriented-assistive'

export type SuccessfulAPIResult<T> = {
  status: number
  ok: true
  payload: T
}

export type FailedAPIResult<T = never> = {
  status: number
  ok: false
  error: string
  response?: Response
  payload?: T
}

export type APIResult<T, TError = never> = SuccessfulAPIResult<T> | FailedAPIResult<TError>

type SuccessfulAPIStreamingResult = {
  status: number
  ok: true
  response: Response
}

export type APIStreamingResult = SuccessfulAPIStreamingResult | FailedAPIResult

export interface CopilotChatPayload {
  agentsPath: string
  apiURL: string
  apiVersion?: string
  currentUserLogin: string
  customInstructions?: CopilotCustomInstructions
  customCopilotsEnabled?: boolean
  renderKnowledgeBases?: boolean
  optedInToPreviewFeatures: boolean
  optedInToUserFeedback: boolean
  renderAttachKnowledgeBaseHerePopover?: boolean
  renderKnowledgeBaseAttachedToChatPopover?: boolean
  renderBetaLabel?: boolean
  reviewLab: boolean
  hasCEorCBAccess?: boolean
  licenseType: CopilotLicenseType
  plan?: CopilotPlan
  quotas?: CopilotChatEntitlementQuotas
  personalInstructions?: string | null
  sharedThreadChannel?: string | null
  autoSubmit?: boolean
}

export type Icebreaker = {
  id: string
  message: string
  titleHtml: string
  icon: string
  color: string
}

export interface Icebreakers {
  instructional: Icebreaker[]
  functional: Icebreaker[]
  interactional: Icebreaker[]
}

export type StarterGroup = {
  id: string
  name: string
  color: string
  icon: string
  entries: StarterEntry[]
}

export type StarterEntry = {
  id: string
  message: string
  titleHtml: SafeHTMLString
}

export interface Starter {
  'files-group': StarterGroup
  'pull-requests-group': StarterGroup
  'issues-group': StarterGroup
  'git-group': StarterGroup
}

/**
 * A model as returned from CAPI
 */
export interface CopilotModel {
  id: string
  name: string
  version: string
  vendor: string
  preview: boolean
  model_picker_enabled: boolean
  capabilities: {
    family: string
    limits: {
      max_prompt_tokens: number
      vision?: {
        supported_media_types: string[]
      }
    }
    supports: {
      tool_calls?: boolean
      parallel_tool_calls?: boolean
      vision?: boolean
    }
    tokenizer: string
    type: string
  }
  policy?: {
    state: CopilotModelPolicyState
    terms?: string
  }
  billing?: {
    is_premium: boolean
    restricted_to?: CopilotPlan[]
    multiplier: number
  }
  is_chat_default?: boolean
  is_chat_fallback?: boolean
}

export type CopilotModelPolicyState = 'enabled' | 'disabled' | 'unconfigured'

/**
 * A model as returned from CAPI, which is usable for chat and
 * augmented with useful properties
 */
export interface CopilotChatModel extends CopilotModel {
  displayName: string
  hasLimitedCapabilities: boolean
  isThirdParty: boolean
  logoURL?: string
  capabilities: CopilotModel['capabilities'] & {type: 'chat'}
}

export interface CopilotChatSettings {
  instructionPrompt: string
  temperature: number
  skillOverrides: Tool[]
}

export interface Tool {
  slug: string | undefined
  description: string | undefined
  enabled: boolean
}

export const DialogType = {
  Experiments: 'experiements',
  Prompt: 'prompt',
  None: 'none',
} as const

export type DialogType = (typeof DialogType)[keyof typeof DialogType]

export const CopilotLicenseType = {
  Unlicensed: 'unlicensed',
  LicensedFull: 'licensed_full',
  LicensedLimited: 'licensed_limited',
} as const

export type CopilotLicenseType = (typeof CopilotLicenseType)[keyof typeof CopilotLicenseType]

export const CopilotPlan = {
  IndividualFree: 'free',
  IndividualPro: 'pro',
  IndividualProPlus: 'pro_plus',
  Business: 'business',
  Enterprise: 'enterprise',
} as const

export type CopilotPlan = (typeof CopilotPlan)[keyof typeof CopilotPlan]
export interface CopilotChatEntitlementQuotas {
  limits: {
    chat: number
    premiumInteractions?: number
  }
  remaining: {
    chat: number
    premiumInteractions?: number
    chatPercentage?: number
    premiumInteractionsPercentage?: number
  }
  resetDate: string
  overagesEnabled: boolean
}

export type ClientSideSkillParameters = {
  type: string
  required?: string[]
  properties: ClientSideSkillParametersProperties
}

type ClientSideSkillParametersProperties = {
  [key: string]: {
    type: string
    required?: string[]
    description: string
    properties?: ClientSideSkillParametersProperties
    enum?: string[]
  }
}

export type ClientSideSkillDefinition = {
  function: {
    name: string
    description: string
    parameters?: ClientSideSkillParameters
  }
  type: 'function'
}

export type ToolCallResult = {
  id: string
  type: 'function'
  functionCallResult: ClientSideSkillResult
}

type ClientSideSkillResult = {
  name: string
  arguments: string
  result: string
}

export const NullMessageId = 'NULL_MESSAGE'

export interface AutocompleteIssue {
  number: number
  title: string
  state: string
}

export interface AutocompletePullRequest {
  number: number
  title: string
  state: string
}

export interface AutocompleteDiscussion {
  number: number
  title: string
  state: string
}
