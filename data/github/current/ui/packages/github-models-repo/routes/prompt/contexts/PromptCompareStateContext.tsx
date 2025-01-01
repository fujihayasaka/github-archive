import {createContext, useContext, type PropsWithChildren} from 'react'
import type {PromptCompareState} from '../prompt-compare-state'
import type {PromptConfig} from '../prompts'

export const initialPromptCompareState = (
  prompts: PromptConfig[],
  overrides: Partial<PromptCompareState> = {},
): PromptCompareState => {
  return {
    error: undefined,
    isLoading: false,

    variables: {},

    prompts,
    isDirty: false,

    messages: [],

    compare: {
      isRunning: false,
      rows: [],
      result: [],
      evaluators: [],
    },
    ...overrides,
  }
}

const PromptCompareStateContext = createContext<PromptCompareState>(initialPromptCompareState([]))

export function usePromptCompareState() {
  return useContext(PromptCompareStateContext)
}

export const PromptCompareStateProvider = ({children, state}: PropsWithChildren<{state: PromptCompareState}>) => {
  return <PromptCompareStateContext.Provider value={state}>{children}</PromptCompareStateContext.Provider>
}
