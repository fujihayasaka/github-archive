import type {Category, FeaturedModel, Model} from '@github-ui/marketplace-common'
import type {SafeHTMLString} from '@github-ui/safe-html'

// We want to use the playground-types in external tooling as well
// eslint-disable-next-line no-barrel-files/no-barrel-files
export * from './utils/playground-types'

export type AuthTokenResult = {
  token: string | undefined
  expiration: string | undefined
}

export type TextInputs = {
  type: 'text'
  text: string
}

export type ImageInputs = {
  type: 'image_url'
  image_url: {url: string}
}

export type ToolInputs = {
  type: 'tool_calls'
  tool_calls: ToolCall[]
}

type MultiModalContent = TextInputs | ImageInputs | ToolInputs

export type MessageContent = string | MultiModalContent[]

export type PlaygroundAPIMessage = {
  role: PlaygroundAPIMessageAuthor
  content: MessageContent
  tool_calls?: ToolCall[]
}

export const PlaygroundAPIMessageAuthorValues = ['user', 'system', 'assistant', 'error', 'tool', 'developer'] as const
export type PlaygroundAPIMessageAuthor = (typeof PlaygroundAPIMessageAuthorValues)[number]
export const PlaygroundAPIMessageAuthorValuesUser = 'user' as PlaygroundAPIMessageAuthor
export const PlaygroundAPIMessageAuthorValuesSystem = 'system' as PlaygroundAPIMessageAuthor

export type PlaygroundMessage = {
  timestamp: Date
  message: MessageContent
  role: PlaygroundAPIMessageAuthor
  tool_call_id?: string
  tool_calls?: ToolCall[]
}

export type ModelDetails = {
  catalogData: Model
  modelInputSchema: ModelInputSchema
  gettingStarted: GettingStarted
}

export type GettingStarted = Record<string, ShowModelGettingStartedPayloadLanguageEntry>

export interface GettingStartedPayload extends ShowModelPayload {
  gettingStarted: GettingStarted
}

export type ShowModelGettingStartedPayloadLanguageEntry = {
  name: string
  sdks: Record<string, ShowModelGettingStartedPayloadSDKEntry>
}

export type ShowModelGettingStartedPayloadSDKEntry = {
  name: string
  content: string
  tocHeadings: MarkdownHeadingsTocItem[]
  codeSamples: string
}

/* eslint-disable-next-line @typescript-eslint/no-explicit-any */
export type PlaygroundRequestParameters = Record<string, any>

// These represent the type of output that we can ask the model to return
// https://platform.openai.com/docs/api-reference/chat/create#chat-create-response_format
export type PlaygroundResponseFormat = 'text' | 'json_object' | 'json_schema'

export type ModelState = {
  catalogData: Model
  modelInputSchema?: ModelInputSchema
  gettingStarted: GettingStarted
  messages: PlaygroundMessage[]
  isLoading: boolean
  systemPrompt: string
  responseFormat: PlaygroundResponseFormat
  jsonSchema?: string
  isUseIndexSelected: boolean
  chatInput: MessageContent
  chatClosed: boolean
  parameters: PlaygroundRequestParameters
  parametersHasChanges: boolean
  tokenUsage: TokenUsage
  usageStats: UsageStats
}

export type TokenUsage = {
  lastMessageInputTokens: number
  totalInputTokens: number
  lastMessageOutputTokens: number
  totalOutputTokens: number
  lastMessageLatency: number
}

export type UsageStats = {
  lastMessageLatency: number
  totalLatency: number
}

export type MessagePair = {
  assistant: string
  user: string
}

export type PlaygroundState = {
  syncInputs: boolean
  models: ModelState[]
}

export type PlaygroundStateAction =
  | {type: 'SET_IS_LOADING'; payload: {index: number; isLoading: boolean}}
  | {type: 'SET_MESSAGES'; payload: {index: number; messages: PlaygroundMessage[]}}
  | {type: 'SET_PARAMETERS'; payload: {index: number; parameters: PlaygroundRequestParameters}}
  | {type: 'SET_SYSTEM_PROMPT'; payload: {index: number; systemPrompt: string}}
  | {type: 'SET_IS_USE_INDEX_SELECTED'; payload: {index: number; isUseIndexSelected: boolean}}
  | {type: 'SET_CHAT_CLOSED'; payload: {index: number; chatClosed: boolean}}
  | {type: 'SET_CHAT_INPUT'; payload: {index: number; chatInput: MessageContent}}
  | {type: 'SET_PARAMETERS_HAS_CHANGES'; payload: {index: number; parametersHasChanges: boolean}}
  | {type: 'SET_RESPONSE_FORMAT'; payload: {index: number; responseFormat: PlaygroundResponseFormat}}
  | {type: 'SET_JSON_SCHEMA'; payload: {index: number; jsonSchema: string}}
  | {type: 'SET_MODEL_STATE'; payload: {index: number; modelState: ModelState}}
  | {type: 'REMOVE_MODEL'; payload: {index: number}}
  | {type: 'SET_SELECTED_LANGUAGE'; payload: {selectedLanguage: string}}
  | {type: 'SET_SELECTED_SDK'; payload: {selectedSDK: string}}
  | {type: 'SET_SYNC_INPUTS'; payload: {syncInputs: boolean}}
  | {type: 'SET_TOKEN_USAGE'; payload: {index: number; tokenUsage: TokenUsage}}
  | {type: 'SET_USAGE_STATS'; payload: {index: number; usageStats: UsageStats}}
  | {type: 'INCREMENT_TOKEN_USAGE'; payload: {index: number}}

export type ModelInputChangeParams = {
  key: string
  value: ModelParameterValue
  validate: boolean
}

export const SidebarSelectionOptions = {
  PARAMETERS: 0,
  DETAILS: 1,
} as const

export type SidebarSelectionOptions = (typeof SidebarSelectionOptions)[keyof typeof SidebarSelectionOptions]

export type IndexModelsPayload = {
  models: Model[]
  categories: {
    apps: Category[]
    actions: Category[]
  }
  playgroundUrl?: string
  restrictedModels?: string[]
  promptExtractionCodeSnippet?: string
}

export type MarkdownHeadingsTocItem = {
  level: number
  text: SafeHTMLString
  anchor: string
  htmlText: SafeHTMLString
}

export type ShowModelPayload = {
  model: Model
  modelReadme: SafeHTMLString
  modelInputSchema: ModelInputSchema
  readmeToc: MarkdownHeadingsTocItem[]
  modelTransparencyContent: SafeHTMLString
  playgroundUrl: string
  miniplaygroundIcebreaker?: string
  modelLicense: SafeHTMLString
  modelEvaluation: SafeHTMLString
  canProvideAdditionalFeedback: boolean
  isLoggedIn: boolean
  restrictedModels: string[]
  comparedModelDetails?: ModelDetails
  appliedPreset?: Preset
  featuredModels?: FeaturedModel[]
  improvedPromptModel?: Model
  promptExtractionModel?: Model
  promptFeedbackBannerDismissed?: boolean
}

export type ModelInputSchema =
  | {
      sampleInputs?: Array<{messages?: Array<{content?: string}>}>
      parameters?: ModelInputSchemaParameter[]
      capabilities?: ModelInputSchemaCapabilities
    }
  | undefined

/* eslint-disable-next-line @typescript-eslint/no-explicit-any */
export type ModelParameterValue = number | string | boolean | any[]

export type ModelInputSchemaParameter = {
  key: string
  type: 'number' | 'integer' | 'array' | 'string' | 'boolean' | 'multiple_choice'
  payloadPath: string
  default?: ModelParameterValue
  min?: number
  max?: number
  required: boolean
  description?: string
  friendlyName?: string
  options?: string[]
  selectionMode?: 'single' | 'multiple'
}

type ModelInputSchemaCapabilities = {
  systemPrompt?: boolean
  chat?: Record<string, number>
}

export type PresetsPayload = {
  presets: Preset[]
  limit_per_user: number
}

export type PresetPayload = {
  name: string
  parameters: Record<string, ModelParameterValue>
  private: boolean
}

export type Preset = PresetPayload & {
  urlIdentifier: string
}

export interface ModelClient {
  sendMessage(
    panel: number,
    model: Model,
    messages: PlaygroundMessage[],
    parameters: PlaygroundRequestParameters,
    responseFormat: PlaygroundResponseFormat,
    systemPrompt: string | null,
    jsonSchema?: string,
  ): AsyncGenerator<ModelClientSendMessageResponse, TokenUsageInfo | undefined, unknown>
}

export type ModelClientSendMessageResponse = {
  message: PlaygroundMessage
  tokenUsage?: TokenUsageInfo
  reachedMaxTokens?: boolean
}

export type TokenUsageInfo = {inputTokens: number; outputTokens: number}

export type ModelSnippet = {
  friendly_name: string
  sdks: {
    [key in 'azure-ai-inference' | 'curl']: {
      friendly_name: string
      code: string
    }
  }
}

export type SearchServiceResponse = {
  apiKey: string
  endpoint: string
  indexName: string
  indexStats: {
    documentCount: number
    files: Array<{
      name: string
      searchDocsCount: number
    }>
  }
  indexerLastExecutionResult: 'TransientFailure' | 'Success' | 'InProgress' | 'Reset' | null
  indexerStatus: 'Error' | 'Running' | 'Unknown' | null
}

export type Index = {
  name: string
  endpoint?: string
  status: SearchServiceResponse['indexerLastExecutionResult']
  files: Array<{name: string; size: number}>
}

export type RAGContextType = {
  index: Index | null
  setIndex: React.Dispatch<React.SetStateAction<Index | null>>
  isFetchingIndex: boolean
  pollUntilCompleted: () => Promise<void>
}

export type ToolCall = {
  id: string
  index: number
  type: 'function'
  function: {
    arguments: string
    name: string
  }
}

export type ChatCompletionFinishReason = 'stop' | 'timeout' | 'max_tokens' | 'tool_calls' | 'length'

export type ChatCompletionChunk = {
  choices: Array<{
    index: number
    finish_reason: ChatCompletionFinishReason | null
    delta?: {
      content: string
      tool_call_id?: string
      tool_calls?: ToolCall[]
    }
  }>
  usage?: {
    prompt_tokens: number
    completion_tokens: number
  }
}

export type Reader = ReadableStreamDefaultReader<Uint8Array>

export type ImprovePromptDialogState = 'suggest' | 'confirm' | 'closed'

export type Prompt = 'system' | 'user'

export type ModelItemInput = {
  text: string
  leadingVisual: React.ElementType
  item: FeaturedModel & Pick<Model, 'task'>
  id: string
}

/**
 * Includes properties of a model necessary for emitting an analytics event about that model.
 */
export type AnalyticalModel = Pick<FeaturedModel, 'publisher' | 'registry' | 'name'>

/**
 * Includes properties of a model necessary for sending messages to the model.
 */
export type MessageableModel = AnalyticalModel &
  Pick<Model, 'capabilities'> & {
    original_name: string
    publisherSlug: string
  }
