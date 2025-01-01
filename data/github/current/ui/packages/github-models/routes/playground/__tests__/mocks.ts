import {PUBLISHER} from '../../../utils/normalize-model-strings'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {modelPlaygroundPath} from '@github-ui/paths'
import {Feedback, type FeedbackState} from '../components/GettingStartedDialog/types'
import type {
  GettingStarted,
  GettingStartedPayload,
  ModelDetails,
  ModelInputSchemaParameter,
  ModelState,
  PlaygroundMessage,
  PlaygroundRequestParameters,
  Preset,
  TokenUsage,
  UsageStats,
} from '../../../types'
import type {Model} from '@github-ui/marketplace-common'
import type {ModelPersistentUIState} from '../../../utils/playground-local-storage'
import {defaultResponseFormat} from '../../../utils/model-state'

export const mockFeedbackState: FeedbackState = {
  satisfaction: Feedback.NEGATIVE,
  reasons: ['harmful'],
  feedbackText: 'not good',
  contactConsent: false,
  model: 'my-test-model',
}

export const mockModel: Model = {
  id: 'test-model-1',
  registry: 'azureopenai',
  name: 'my-test-model',
  original_name: 'my-test-model-original',
  friendly_name: 'My Test Model',
  publisher: PUBLISHER.OpenAI,
  task: 'chat-completion',
  description: 'This is a great model.',
  summary: 'Use this model to do stuff.',
  license: 'MIT',
  logo_url: 'http://example.com/logo.png',
  tags: ['chat', 'neat'],
  rate_limit_tier: 'medium-ish',
  supported_languages: ['en', 'zh', 'fr'],
  max_output_tokens: 123000,
  max_input_tokens: 456000,
  training_data_date: '2022-02-02',
  evaluation: 'We think you will love this model.',
  notes: 'This model is great for chat completion.',
  supported_input_modalities: ['text', 'postcard'],
  supported_output_modalities: ['fax'],
  // in real world use these are base64 encoded svg strings, they are shortened here for readability
  light_mode_icon: 'dayModejaisdflj',
  dark_mode_icon: 'nightModejaisdflj',
}

export const mockO1Model: Model = {
  id: 'test-o1-model',
  registry: 'azureopenai',
  name: 'o1-mini',
  original_name: 'o1-mini',
  friendly_name: 'O1 Mini',
  publisher: 'Open AI',
  task: 'chat-completion',
  description: 'This is a great model.',
  summary: 'Use this model to do stuff.',
  license: 'MIT',
  logo_url: 'http://example.com/logo.png',
  light_mode_icon: '',
  dark_mode_icon: '',
  tags: ['chat', 'neat'],
  rate_limit_tier: 'medium-ish',
  supported_languages: ['English', 'Mandarin'],
  max_output_tokens: 123,
  max_input_tokens: 456,
  training_data_date: '2022-02-02',
  evaluation: 'We think you will love this model.',
  notes: 'This model is great for chat completion.',
  supported_input_modalities: ['text', 'postcard'],
  supported_output_modalities: ['fax'],
}

export const mockModelIntegerInputSchemaParameter: ModelInputSchemaParameter = {
  key: 'max_tokens',
  type: 'integer',
  payloadPath: 'max_tokens',
  default: 2048,
  min: 100,
  max: 4096,
  required: true,
}

export const mockModelNumericInputSchemaParameter: ModelInputSchemaParameter = {
  key: 'temperature',
  type: 'number',
  payloadPath: 'temperature',
  default: 0.8,
  max: 1,
  min: 0,
  required: false,
}

export const mockModelBooleanInputSchemaParameter: ModelInputSchemaParameter = {
  friendlyName: 'Turn it to 11?',
  payloadPath: 'turn-to-eleven',
  type: 'boolean',
  required: false,
  key: 'turn_to_eleven',
}

export const mockModelArrayInputSchemaParameter: ModelInputSchemaParameter = {
  key: 'tags',
  type: 'array',
  payloadPath: 'tags',
  required: false,
}

export const mockModelStringInputSchemaParameter: ModelInputSchemaParameter = {
  key: 'stop',
  type: 'string',
  payloadPath: 'stop',
  required: false,
}

export const mockModelMultipleChoiceInputSchemaParameter: ModelInputSchemaParameter = {
  key: 'reasoning_effort',
  type: 'multiple_choice',
  selectionMode: 'single',
  payloadPath: 'reasoning_effort',
  default: 'high',
  options: ['high', 'medium', 'low'],
  required: false,
}

export const mockModelInputSchemaParameters: ModelInputSchemaParameter[] = [
  mockModelIntegerInputSchemaParameter,
  mockModelNumericInputSchemaParameter,
  {
    key: 'top_p',
    type: 'number',
    payloadPath: 'top_p',
    default: 0.1,
    max: 1,
    min: 0.01,
    required: false,
  },
  mockModelStringInputSchemaParameter,
]

export function mockGettingStartedPayload(overrides: Partial<GettingStartedPayload> = {}): GettingStartedPayload {
  const basePayload: GettingStartedPayload = {
    gettingStarted: mockGettingStarted,
    model: mockModel,
    modelInputSchema: mockModelInputSchema,
    modelReadme: 'Sample readme content' as SafeHTMLString,
    modelLicense: mockModel.license as SafeHTMLString,
    readmeToc: [],
    modelTransparencyContent: 'Sample transparency content' as SafeHTMLString,
    playgroundUrl: modelPlaygroundPath(mockModel),
    modelEvaluation: mockModel.evaluation as SafeHTMLString,
    canProvideAdditionalFeedback: false,
    isLoggedIn: true,
    restrictedModels: ['o1-mini', 'o1', 'o1-preview'],
  }
  return {...basePayload, ...overrides}
}

export const mockModelInputSchema = {
  examples: [],
  sampleInputs: [{messages: [{content: 'sample message'}]}],
  inputs: [],
  outputs: [],
  fixedParameters: [],
  capabilities: {},
  type: '',
  version: '',
  behavior: '',
  parameters: mockModelInputSchemaParameters,
}

export const mockO1ModelInputSchema = {
  examples: [],
  sampleInputs: [{messages: [{content: 'sample message'}]}],
  inputs: [],
  outputs: [],
  fixedParameters: [],
  capabilities: {},
  type: '',
  version: '',
  behavior: '',
  parameters: [...mockModelInputSchemaParameters, mockModelMultipleChoiceInputSchemaParameter],
}

export const mockGettingStarted: GettingStarted = {
  python: {
    name: 'Python',
    sdks: {
      'azure-python-sdk': {
        name: 'Azure Python SDK',
        tocHeadings: [
          {
            level: 1,
            text: 'Azure Python SDK Heading 1' as SafeHTMLString,
            anchor: 'azure-python-sdk-heading-1',
            htmlText: 'Azure Python SDK Heading 1' as SafeHTMLString,
          },
          {
            level: 2,
            text: 'Azure Python SDK Heading 2' as SafeHTMLString,
            anchor: 'azure-python-sdk-heading-2',
            htmlText: 'Azure Python SDK Heading 2' as SafeHTMLString,
          },
        ],
        content: 'azure-python-sdk content',
        codeSamples: 'azure-python-sdk code sample',
      },
      'azure-python-sdk-2': {
        name: 'Azure Python SDK 2',
        tocHeadings: [
          {
            level: 1,
            text: 'Azure Python SDK 2 Heading 1' as SafeHTMLString,
            anchor: 'azure-python-sdk-2-heading-1',
            htmlText: 'Azure Python SDK 2 Heading 1' as SafeHTMLString,
          },
          {
            level: 2,
            text: 'Azure Python SDK 2 Heading 2' as SafeHTMLString,
            anchor: 'azure-python-sdk-2-heading-2',
            htmlText: 'Azure Python SDK 2 Heading 2' as SafeHTMLString,
          },
        ],
        content: 'azure-python-sdk-2 content',
        codeSamples: 'azure-python-sdk-2 code sample',
      },
    },
  },
  js: {
    name: 'JavaScript',
    sdks: {
      'azure-javascript-sdk': {
        name: 'Azure JavaScript SDK',
        tocHeadings: [
          {
            level: 1,
            text: 'Azure JavaScript SDK Heading 1' as SafeHTMLString,
            anchor: 'azure-javascript-sdk-heading-1',
            htmlText: 'Azure JavaScript SDK Heading 1' as SafeHTMLString,
          },
          {
            level: 2,
            text: 'Azure JavaScript SDK Heading 2' as SafeHTMLString,
            anchor: 'azure-javascript-sdk-heading-2',
            htmlText: 'Azure JavaScript SDK Heading 2' as SafeHTMLString,
          },
        ],
        content: 'azure-javascript-sdk content',
        codeSamples: 'azure-javascript-sdk code sample',
      },
      'azure-javascript-sdk-2': {
        name: 'Azure JavaScript SDK 2',
        tocHeadings: [
          {
            level: 1,
            text: 'Azure JavaScript SDK 2 Heading 1' as SafeHTMLString,
            anchor: 'azure-javascript-sdk-2-heading-1',
            htmlText: 'Azure JavaScript SDK 2 Heading 1' as SafeHTMLString,
          },
          {
            level: 2,
            text: 'Azure JavaScript SDK 2 Heading 2' as SafeHTMLString,
            anchor: 'azure-javascript-sdk-2-heading-2',
            htmlText: 'Azure JavaScript SDK 2 Heading 2' as SafeHTMLString,
          },
        ],
        content: 'azure-javascript-sdk-2 content',
        codeSamples: 'azure-javascript-sdk-2 code sample',
      },
    },
  },
  go: {
    name: 'Go',
    sdks: {
      'azure-go-sdk': {
        name: 'Azure Go SDK',
        tocHeadings: [
          {
            level: 1,
            text: 'Azure Go SDK Heading 1' as SafeHTMLString,
            anchor: 'azure-go-sdk-heading-1',
            htmlText: 'Azure Go SDK Heading 1' as SafeHTMLString,
          },
          {
            level: 2,
            text: 'Azure Go SDK Heading 2' as SafeHTMLString,
            anchor: 'azure-go-sdk-heading-2',
            htmlText: 'Azure Go SDK Heading 2' as SafeHTMLString,
          },
        ],
        content: 'azure-go-sdk content',
        codeSamples: '', // intentionally empty
      },
    },
  },
  csharp: {
    name: 'C#',
    sdks: {},
  },
}

export const mockModelDetails: ModelDetails = {
  catalogData: mockModel,
  modelInputSchema: mockModelInputSchema,
  gettingStarted: mockGettingStarted,
}

export const mockDefaultParameters: PlaygroundRequestParameters = {
  max_tokens: 2048,
  temperature: 0.8,
  top_p: 0.1,
  stop: undefined,
}

export const mockTokenUsage: TokenUsage = {
  lastMessageInputTokens: 0,
  lastMessageOutputTokens: 0,
  totalInputTokens: 0,
  totalOutputTokens: 0,
}

export const mockUsageStats: UsageStats = {
  lastMessageLatency: 0,
  totalLatency: 0,
}

export const mockModelState: ModelState = {
  catalogData: mockModel,
  modelInputSchema: mockModelInputSchema,
  gettingStarted: mockGettingStarted,
  messages: [],
  isLoading: false,
  systemPrompt: '',
  isUseIndexSelected: false,
  chatInput: '',
  responseFormat: defaultResponseFormat,
  jsonSchema: '',
  chatClosed: false,
  parameters: mockDefaultParameters,
  parametersHasChanges: false,
  tokenUsage: mockTokenUsage,
  usageStats: mockUsageStats,
}

export const mockO1ModelState: ModelState = {
  catalogData: mockModel,
  modelInputSchema: mockO1ModelInputSchema,
  gettingStarted: mockGettingStarted,
  messages: [],
  isLoading: false,
  systemPrompt: '',
  isUseIndexSelected: false,
  chatInput: '',
  responseFormat: defaultResponseFormat,
  chatClosed: false,
  parameters: mockDefaultParameters,
  parametersHasChanges: false,
  tokenUsage: mockTokenUsage,
  usageStats: mockUsageStats,
}

export const mockNewMessages: PlaygroundMessage[] = [
  {
    role: 'user',
    message: 'test message',
    timestamp: new Date('2024-01-01T00:00:00+00:00'),
  },
  {
    role: 'assistant',
    message: 'test response',
    timestamp: new Date('2024-01-01T00:00:00+00:01'),
  },
]

export const mockNewSystemPrompt = 'Respond in one sentence'

export const mockNewParameters: PlaygroundRequestParameters = {
  max_tokens: 1000,
  temperature: 1,
  top_p: 1,
  stop: [],
}

export const mockChatInput = 'What is'

export const mockPreset: Preset = {
  name: 'Preset A',
  urlIdentifier: 'monalisa/preset-a',
  parameters: {
    system_prompt: 'Respond in one sentence',
    chat_prompt: 'Whats the meaning of life?',
  },
  private: true,
}

export const mockLocalStorageUiState: ModelPersistentUIState = {
  sidebarTab: 0,
  showSidebar: true,
  preferredLanguage: 'python',
  preferredSdk: 'azure-python-sdk',
}
