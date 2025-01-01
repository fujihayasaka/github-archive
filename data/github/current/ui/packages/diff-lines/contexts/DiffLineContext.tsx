import type {DiffAnchor} from '@github-ui/diffs/types'
import type {PropsWithChildren} from 'react'
import {createContext, useContext, useMemo} from 'react'

import type {HunkData} from '../helpers/hunk-data-helpers'
import type {ClientDiffLine, DiffContext} from '../types'
import type {ThreadSummary} from '@github-ui/conversations'

export type DiffLineContextData = {
  currentHunk?: HunkData
  diffEntryId: string
  diffLine: ClientDiffLine
  fileAnchor: DiffAnchor
  fileLineCount: number
  filePath: string
  isLeftSide?: boolean
  isRowSelected: boolean
  isSplit: boolean
  modifiedLineThreads?: ThreadSummary[]
  modifiedLineHasThreads?: boolean
  modifiedLineThreadsConnectionId?: string
  nextHunk?: HunkData
  originalLineThreads?: ThreadSummary[]
  originalLineHasThreads?: boolean
  originalLineThreadsConnectionId?: string
  previousHunk?: HunkData
  rowId: string
  diffContext?: DiffContext
  setInGridMode?: (inGridMode: boolean) => void
}

const DiffLineContext = createContext<DiffLineContextData | null>(null)

export function DiffLineContextProvider({
  children,
  currentHunk,
  diffEntryId,
  diffLine,
  fileAnchor,
  fileLineCount,
  filePath,
  isLeftSide,
  isRowSelected = false,
  isSplit,
  modifiedLineThreads,
  modifiedLineThreadsConnectionId,
  nextHunk,
  originalLineThreads,
  originalLineThreadsConnectionId,
  previousHunk,
  rowId,
  diffContext,
  setInGridMode,
}: PropsWithChildren<DiffLineContextData>) {
  const contextData = useMemo(
    () => ({
      currentHunk,
      diffEntryId,
      diffLine,
      fileAnchor,
      fileLineCount,
      filePath,
      isLeftSide,
      isRowSelected,
      isSplit,
      modifiedLineThreads,
      modifiedLineHasThreads: modifiedLineThreads && modifiedLineThreads.length > 0,
      modifiedLineThreadsConnectionId,
      nextHunk,
      originalLineThreads,
      originalLineHasThreads: originalLineThreads && originalLineThreads.length > 0,
      originalLineThreadsConnectionId,
      previousHunk,
      rowId,
      diffContext,
      setInGridMode,
    }),
    [
      currentHunk,
      diffEntryId,
      diffLine,
      fileAnchor,
      fileLineCount,
      filePath,
      isLeftSide,
      isRowSelected,
      isSplit,
      modifiedLineThreads,
      modifiedLineThreadsConnectionId,
      nextHunk,
      originalLineThreads,
      originalLineThreadsConnectionId,
      previousHunk,
      rowId,
      diffContext,
      setInGridMode,
    ],
  )

  return <DiffLineContext.Provider value={contextData}>{children}</DiffLineContext.Provider>
}

export function useDiffLineContext(): DiffLineContextData {
  const contextData = useContext(DiffLineContext)
  if (!contextData) {
    throw new Error('useDiffLineContext must be used within a DiffLineContextProvider')
  }

  return contextData
}
