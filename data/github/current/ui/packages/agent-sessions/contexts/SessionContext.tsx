import {createContext, useContext, useMemo} from 'react'
import type {Session} from '../types/session'

interface SessionContextType {
  session: Session
}

export const SessionContext = createContext<SessionContextType | undefined>(undefined)

export function useSessionContext() {
  const context = useContext(SessionContext)
  if (!context) {
    throw new Error('useSessionContext must be used within a SessionContextProvider')
  }
  return context
}

interface SessionContextProviderProps extends SessionContextType {
  children: React.ReactNode
}

export function SessionContextProvider({session, children}: SessionContextProviderProps) {
  const value = useMemo(() => ({session}), [session])
  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
}
