import {mockModelState} from '../../../playground/__tests__/mocks'
import type {PromptEvalsState} from '../../prompt-evals-state'

export function mockPromptEvalsState(overrides: Partial<PromptEvalsState> = {}): PromptEvalsState {
  const defaults: PromptEvalsState = {
    selectedLanguage: 'js',
    selectedSDK: '',
    error: undefined,
    variables: {},
    systemPrompt: '',
    prompt: '',
    evals: {
      isRunning: false,
      rows: [],
      result: [],
      evaluators: [],
    },
    model: mockModelState,
  }
  return {...defaults, ...overrides}
}
