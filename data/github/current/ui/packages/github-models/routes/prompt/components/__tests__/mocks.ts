import {mockModelState} from '../../../playground/__tests__/mocks'
import type {PromptState} from '../../prompt-state'

export function mockPromptState(overrides: Partial<PromptState> = {}): PromptState {
  const defaults: PromptState = {
    selectedLanguage: 'js',
    selectedSDK: '',
    error: undefined,
    variables: {},
    systemPrompt: '',
    prompt: '',
    model: mockModelState,
  }
  return {...defaults, ...overrides}
}
