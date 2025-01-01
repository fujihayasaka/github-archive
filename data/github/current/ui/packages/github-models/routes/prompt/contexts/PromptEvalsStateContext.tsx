import {createContext, useContext, type PropsWithChildren} from 'react'
import type {PromptEvalsState} from '../prompt-evals-state'
import {getPromptEvalsLocalStorage} from '../../../utils/prompt-evals-local-storage'

export const initialPromptEvalsState = (overrides: Partial<PromptEvalsState> = {}): PromptEvalsState => {
  const localStorage = getPromptEvalsLocalStorage()
  return {
    selectedLanguage: 'js',
    selectedSDK: '',
    error: undefined,
    variables: localStorage?.variables ?? {},
    systemPrompt: localStorage?.systemPrompt,
    prompt: localStorage?.prompt ?? '',
    messagePairs: localStorage?.messagePairs ?? [],
    evals: {
      isRunning: false,
      rows: localStorage?.evals?.rows ?? [],
      result: localStorage?.evals?.result ?? [],
      evaluators: localStorage?.evals?.evaluators ?? [],
    },
    ...overrides,
  } as PromptEvalsState
}

const PromptEvalsStateContext = createContext<PromptEvalsState>(initialPromptEvalsState({}))

export function usePromptEvalsState() {
  return useContext(PromptEvalsStateContext)
}

export const PromptEvalsStateProvider = ({children, state}: PropsWithChildren<{state: PromptEvalsState}>) => {
  return <PromptEvalsStateContext.Provider value={state}>{children}</PromptEvalsStateContext.Provider>
}
