import {
  createContext,
  type Dispatch,
  type PropsWithChildren,
  type SetStateAction,
  useContext,
  useMemo,
  useState,
} from 'react'
import type {PlaygroundMessage} from '../../../types'

interface MessageHistoryContextProps {
  history: PlaygroundMessage[]
  setHistory: Dispatch<SetStateAction<PlaygroundMessage[]>>
}

const MessageHistoryContext = createContext<MessageHistoryContextProps>({history: [], setHistory: () => {}})

interface MessageHistoryProviderProps extends PropsWithChildren {
  initialHistory?: PlaygroundMessage[]
}

export const MessageHistoryProvider = ({children, initialHistory}: MessageHistoryProviderProps) => {
  const [history, setHistory] = useState<PlaygroundMessage[]>(initialHistory ?? [])
  const value = useMemo(() => ({history, setHistory}) satisfies MessageHistoryContextProps, [history])
  return <MessageHistoryContext.Provider value={value}>{children}</MessageHistoryContext.Provider>
}

export const useMessageHistory = () => {
  return useContext(MessageHistoryContext)
}
