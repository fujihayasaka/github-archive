import {CompletionsApi} from '@github-ui/completions-api'
import {Prompts} from '@github-ui/completions-api/prompts'
import {createContext, type PropsWithChildren, useCallback, useContext, useMemo, useRef} from 'react'

export type CopilotContextData = {
  getCommandSuggestion(input: string, terminalHistory: string): Promise<string | undefined>
}

export const CopilotContext = createContext<CopilotContextData | undefined>(undefined)

const COMPLETIONS_API_USER_AGENT = 'GitHubWorkspaceEditor/0.0.1'

export function CopilotContextProvider({children}: PropsWithChildren) {
  const completionApiRef = useRef(new CompletionsApi(COMPLETIONS_API_USER_AGENT, 'workspace_editor'))

  const getCommandSuggestion = useCallback(
    async (input: string, terminalHistory: string) => {
      const prompt = Prompts.buildTerminalPrompt(input, terminalHistory)
      const response = await completionApiRef.current.complete(prompt, new AbortController().signal)
      const suggestion = Prompts.parseTerminalCompletion(response)
      return suggestion
    },
    [completionApiRef],
  )

  const copilotContextData = useMemo(
    () => ({
      getCommandSuggestion,
    }),
    [getCommandSuggestion],
  )

  return <CopilotContext.Provider value={copilotContextData}>{children}</CopilotContext.Provider>
}

export function useCopilotContext() {
  const context = useContext(CopilotContext)
  if (!context) {
    throw new Error('useCopilotContext must be used within a CopilotContextProvider')
  }

  return context
}
