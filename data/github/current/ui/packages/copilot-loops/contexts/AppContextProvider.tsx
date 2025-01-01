import type {CopilotChatModel} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {createContext, useContext, useMemo} from 'react'

interface AppContextData {
  availableModels: CopilotChatModel[] | null
  previewUrl: string | undefined
  sendChatMessage: (message: string) => void
}

const AppContext = createContext<AppContextData | null>(null)

export function AppContextProvider({
  availableModels,
  previewUrl,
  sendChatMessage,
  children,
}: AppContextData & {children: React.ReactNode}) {
  const contextValue = useMemo(
    () => ({availableModels, previewUrl, sendChatMessage}),
    [availableModels, previewUrl, sendChatMessage],
  )
  return <AppContext.Provider value={contextValue}>{children}</AppContext.Provider>
}

export function useAppContext(): AppContextData {
  const context = useContext(AppContext)
  if (!context) {
    throw new Error('useAppContext must be used within an AppContextProvider')
  }

  return context
}
