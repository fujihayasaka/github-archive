import {createContext, useContext, useState, useMemo, useEffect, useCallback} from 'react'
import type React from 'react'
import {fetchIndex} from '../../../utils/rag-index-manager'
import type {RAGContextType, Index} from '../../../types'

const RAGContext = createContext<RAGContextType>({} as RAGContextType)

type RAGContextProviderProps = {
  children: React.ReactNode
  initialIndex?: Index
  skipInitialIndexFetch?: boolean
}

export const RAGContextProvider = ({children, initialIndex, skipInitialIndexFetch}: RAGContextProviderProps) => {
  const [index, setIndex] = useState<RAGContextType['index']>(initialIndex ?? null)
  const [isFetchingIndex, setIsFetchingIndex] = useState(false)

  useEffect(() => {
    if (initialIndex || skipInitialIndexFetch) return
    pollUntilCompleted()
    // We only want this to run once, so we want an empty dependency array
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const pollUntilCompleted = useCallback(async () => {
    setIsFetchingIndex(true)
    const fetchedIndex = await fetchIndex()
    setIndex(fetchedIndex)

    if (fetchedIndex?.status === 'InProgress' || fetchedIndex?.status === null) {
      // pause for 1000 ms
      await new Promise(resolve => setTimeout(resolve, 1000))

      return await pollUntilCompleted()
    }

    setIsFetchingIndex(false)
  }, [])

  const contextValue = useMemo(
    () => ({index, setIndex, isFetchingIndex, pollUntilCompleted}),
    [index, isFetchingIndex, pollUntilCompleted],
  )

  return <RAGContext.Provider value={contextValue}>{children}</RAGContext.Provider>
}

export const useRAGContext = () => {
  const context = useContext(RAGContext)
  if (context === undefined) {
    throw new Error('useRAGContext must be used within a RAGContextProvider')
  }

  return context
}
