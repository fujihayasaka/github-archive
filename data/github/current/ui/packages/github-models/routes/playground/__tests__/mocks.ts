import {PUBLISHER} from '../../../utils/normalize-model-strings'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {ModelUrlHelper} from '../../../utils/model-url-helper'
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
} from '../../../types'
import type {Model} from '@github-ui/marketplace-common'
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
  max_output_tokens: 123,
  max_input_tokens: 456,
  training_data_date: '2022-02-02',
  model_family: PUBLISHER.OpenAI,
  evaluation: 'We think you will love this model.',
  notes: 'This model is great for chat completion.',
  static_model: null,
  supported_input_modalities: ['text', 'postcard'],
  supported_output_modalities: ['fax'],
  // in real world use these are base64 encoded svg strings, they are shortened here for readability
  light_mode_icon: 'dayModejaisdflj',
  dark_mode_icon: 'nightModejaisdflj',
}

export const mockModelInputSchemaParameters: ModelInputSchemaParameter[] = [
  {
    key: 'max_tokens',
    type: 'integer',
    payloadPath: 'max_tokens',
    default: 2048,
    min: 100,
    max: 4096,
    required: true,
  },
  {
    key: 'temperature',
    type: 'number',
    payloadPath: 'temperature',
    default: 0.8,
    max: 1,
    min: 0,
    required: false,
  },
  {
    key: 'top_p',
    type: 'number',
    payloadPath: 'top_p',
    default: 0.1,
    max: 1,
    min: 0.01,
    required: false,
  },
  {
    key: 'stop',
    type: 'string',
    payloadPath: 'stop',
    required: false,
  },
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
    playgroundUrl: ModelUrlHelper.playgroundUrl(mockModel),
    modelEvaluation: mockModel.evaluation as SafeHTMLString,
    canProvideAdditionalFeedback: false,
    isLoggedIn: true,
    canUseO1Models: true,
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
  javascript: {
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
  chatClosed: false,
  parameters: mockDefaultParameters,
  parametersHasChanges: false,
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
  conversationHistory: [
    {
      role: 'user',
      message: 'test message',
      timestamp: new Date('2024-01-01T00:00:00+00:00'),
    },
  ],
  description: 'Preset A without parameters or conversation history',
  urlIdentifier: 'monalisa/preset-a',
  parameters: {
    system_prompt: 'Respond in one sentence',
    max_tokens: 1000,
    temperature: 1,
    top_p: 1,
    stop: [],
  },
  private: true,
}
