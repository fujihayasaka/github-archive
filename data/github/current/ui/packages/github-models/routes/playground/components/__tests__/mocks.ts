import type {
  MessageContent,
  ModelState,
  PlaygroundMessage,
  PlaygroundRequestParameters,
  PlaygroundState,
} from '../../../../types'
import {mockGettingStarted, mockModel, mockModelInputSchema} from '../../__tests__/mocks'
import type {language} from '../PlaygroundCodeSnippet'
import {mockSDK} from '../GettingStartedDialog/__tests__/mocks'

export const mockStoredMessage = {
  role: 'user',
  message: 'test message',
  timestamp: new Date('2024-01-01T00:00:00+00:00'),
} satisfies PlaygroundMessage

const mockSelectedLanguage: language = 'js'

export function mockModelState(overrides: Partial<ModelState> = {}): ModelState {
  const gettingStarted = Object.assign({}, mockGettingStarted)
  gettingStarted[mockSelectedLanguage] = {
    name: 'JavaScript',
    sdks: {'some-sdk': mockSDK()},
  }
  const baseModelState: ModelState = {
    catalogData: mockModel,
    modelInputSchema: mockModelInputSchema,
    gettingStarted,
    isLoading: false,
    systemPrompt: 'Write a sonnet about the provided content.',
    isUseIndexSelected: false,
    chatClosed: false,
    responseFormat: 'text',
    parametersHasChanges: false,
    messages: [mockStoredMessage],
    chatInput: 'hey write me a sonnet' as MessageContent,
    parameters: {} as PlaygroundRequestParameters,
  }
  return {...baseModelState, ...overrides}
}

// https://developer.mozilla.org/en-US/docs/Web/API/Window/structuredClone
const structuredClone = <T>(val: T): T => JSON.parse(JSON.stringify(val))

export function getImageModelState(modelState: ModelState): ModelState {
  const base = structuredClone(modelState)
  const model = base.catalogData
  model.supported_input_modalities = ['text', 'image']
  // ui/packages/marketplace-react/models/utils/image-validation.ts
  model.model_family = 'Microsoft'
  return base
}

export function mockPlaygroundState(overrides: Partial<PlaygroundState> = {}): PlaygroundState {
  const basePlaygroundState: PlaygroundState = {
    selectedLanguage: mockSelectedLanguage,
    selectedSDK: '',
    syncInputs: false,
    models: [mockModelState()],
  }
  return {...basePlaygroundState, ...overrides}
}

export function setupMatchMediaMock() {
  /**
   * Required for internal usage of matchMedia in primer/react
   * Duplicated from ui/packages/jest/jest-setup.ts
   * this is not implemented in JSDOM, and until it is we'll need to polyfill
   */
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: jest.fn().mockImplementation(query => {
      return {
        matches: false,
        media: query,
        onchange: null,
        addListener: jest.fn(), // deprecated
        removeListener: jest.fn(), // deprecated
        addEventListener: jest.fn(),
        removeEventListener: jest.fn(),
        dispatchEvent: jest.fn(),
      }
    }),
  })
}
