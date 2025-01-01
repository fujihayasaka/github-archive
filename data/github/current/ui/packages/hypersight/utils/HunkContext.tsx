import type {ReactNode} from 'react'
import {createContext, useCallback, useContext, useMemo} from 'react'
import type {DiffHunk} from './types'

interface HunkContextType {
  hunks: DiffHunk[]
  getHunkById: (id: number) => DiffHunk | undefined
}

const HunkContext = createContext<HunkContextType | null>(null)

export function HunkProvider({children, hunks}: {children: ReactNode; hunks: DiffHunk[]}) {
  const getHunkById = useCallback((id: number) => hunks.find(hunk => hunk.hunkId === id), [hunks])
  const value = useMemo(() => ({hunks, getHunkById}), [hunks, getHunkById])

  return <HunkContext.Provider value={value}>{children}</HunkContext.Provider>
}

export function useHunks() {
  const context = useContext(HunkContext)
  if (!context) {
    throw new Error('useHunks must be used within a HunkProvider')
  }
  return context
}
