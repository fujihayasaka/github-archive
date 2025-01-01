import {createContext, useContext, useMemo} from 'react'
import type {Pull} from '../types/pull'

interface PullContextType {
  pull: Pull
}

export const PullContext = createContext<PullContextType | undefined>(undefined)

export function usePullContext() {
  const context = useContext(PullContext)
  if (!context) {
    throw new Error('usePullContext must be used within a PullContextProvider')
  }
  return context
}

interface PullContextProviderProps extends PullContextType {
  children: React.ReactNode
}

export function PullContextProvider({pull, children}: PullContextProviderProps) {
  const value = useMemo(() => ({pull}), [pull])
  return <PullContext.Provider value={value}>{children}</PullContext.Provider>
}
