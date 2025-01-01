import type {CopilotChatModel} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {createContext, useContext} from 'react'

export interface CopilotContextValue {
  prompt: string
  setPrompt: React.Dispatch<React.SetStateAction<string>>
  selectedModel: CopilotChatModel
  setSelectedModel: React.Dispatch<React.SetStateAction<CopilotChatModel>>
}

export const CopilotContext = createContext<CopilotContextValue | undefined>(undefined)

export function useCopilotContext() {
  const context = useContext(CopilotContext)
  if (!context) {
    throw new Error('useCopilotContext must be used within a CopilotContext.Provider')
  }
  return context
}
