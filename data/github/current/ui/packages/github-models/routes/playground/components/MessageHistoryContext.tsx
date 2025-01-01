import {
  createContext,
  type Dispatch,
  type PropsWithChildren,
  type SetStateAction,
  useContext,
  useMemo,
  useState,
} from 'react'
import type {PlaygroundMessage, TokenUsage} from '../../../types'

type SavedHistory = {
  messages: PlaygroundMessage[]
  tokenUsage: TokenUsage
}

interface MessageHistoryContextProps {
  history: SavedHistory
  setHistory: Dispatch<SetStateAction<SavedHistory>>
}

const defaultTokenUsage = {
  lastMessageInputTokens: 0,
  totalInputTokens: 0,
  lastMessageOutputTokens: 0,
  totalOutputTokens: 0,
}

const MessageHistoryContext = createContext<MessageHistoryContextProps>({
  history: {messages: [], tokenUsage: defaultTokenUsage},
  setHistory: () => {},
})

interface MessageHistoryProviderProps extends PropsWithChildren {
  initialMessages?: PlaygroundMessage[]
  initialTokenUsage?: TokenUsage
}

export const MessageHistoryProvider = ({children, initialMessages, initialTokenUsage}: MessageHistoryProviderProps) => {
  const [history, setHistory] = useState<SavedHistory>({
    messages: initialMessages ?? [],
    tokenUsage: initialTokenUsage ?? defaultTokenUsage,
  })
  const value = useMemo(() => ({history, setHistory}) satisfies MessageHistoryContextProps, [history])
  return <MessageHistoryContext.Provider value={value}>{children}</MessageHistoryContext.Provider>
}

export const useMessageHistory = () => {
  return useContext(MessageHistoryContext)
}
