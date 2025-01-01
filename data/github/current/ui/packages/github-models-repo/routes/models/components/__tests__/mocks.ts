import type {GettingStarted} from '@github-ui/github-models'
import type {Model} from '@github-ui/marketplace-common'
import type {SafeHTMLString} from '@github-ui/safe-html'

export const mockGettingStarted = (): GettingStarted => ({
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
})

export const mockModel = (name: string = 'test-model', overrides: Partial<Model> = {}): Model => ({
  id: `${name}-id`,
  registry: `${name}-registry`,
  name,
  original_name: `${name}-original`,
  friendly_name: `${name}-friendly`,
  publisher: `${name}-publisher`,
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
  publisherSlug: 'openai',
  ...overrides,
})
