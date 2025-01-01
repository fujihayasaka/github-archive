import {createContext, useContext, type PropsWithChildren} from 'react'
import type {PromptCompareState} from '../prompt-compare-state'
import type {PromptCollection} from '../prompts'
import type {EvalsRow} from '../types'
import {referencedVariablesInPrompt} from '../variables'

export const initialPromptCompareState = (
  prompts: PromptCollection,
  overrides: Partial<PromptCompareState> = {},
): PromptCompareState => {
  const {testData = [], evaluators = []} = prompts[0] ?? {}

  if (Object.keys(overrides.variables ?? {}).length === 0 && prompts[0]) {
    const referencedVars = referencedVariablesInPrompt(prompts[0])

    // Get the first test data row to prefill variables
    const firstTestData = testData?.[0] as Record<string, unknown> | undefined

    // Initialize variables based on referenced variables in the prompt
    const initialVars: Record<string, string> = {}
    for (const varName of referencedVars) {
      initialVars[varName] = (firstTestData?.[varName] as string) ?? ''
    }

    overrides.variables = initialVars
  }

  return {
    error: undefined,
    isLoading: false,

    variables: overrides.variables ?? {},

    prompts,
    isDirty: false,

    messages: [],

    compare: {
      isRunning: false,
      rows:
        testData?.map(
          (data, index) =>
            ({
              id: index.toString(),
              ...data,
            }) as EvalsRow,
        ) ?? [],
      skippedRowIds: new Set<string>(),
      result: {},
      evaluators,
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
