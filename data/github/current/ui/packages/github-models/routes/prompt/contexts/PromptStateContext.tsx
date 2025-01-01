import {createContext, useContext, type PropsWithChildren} from 'react'
import {getPromptLocalStorage} from '../../../utils/prompt-local-storage'
import type {PromptState} from '../prompt-state'

export const initialPromptState = (overrides: Partial<PromptState> = {}): PromptState => {
  const localStorage = getPromptLocalStorage()
  return {
    selectedLanguage: 'js',
    selectedSDK: '',
    error: undefined,
    variables: localStorage?.variables ?? {},
    systemPrompt: localStorage?.systemPrompt,
    prompt: localStorage?.prompt ?? '',
    messagePairs: localStorage?.messagePairs ?? [],
    ...overrides,
  } as PromptState
}

const PromptStateContext = createContext<PromptState>(initialPromptState({}))

export function usePromptState() {
  return useContext(PromptStateContext)
}

export const PromptStateProvider = ({children, state}: PropsWithChildren<{state: PromptState}>) => {
  return <PromptStateContext.Provider value={state}>{children}</PromptStateContext.Provider>
}
