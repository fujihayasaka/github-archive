import {createContext, useContext, useMemo, useState} from 'react'

export type ContentFilterContext = {
  filteredCategories: Array<{category: string; severity: string}> | undefined
  setFilteredCategories: (filteredCategories: Array<{category: string; severity: string}> | undefined) => void
  isFilteredModalOpen: boolean
  setIsFilteredModalOpen: (isFilteredModalOpen: boolean) => void
  updateFilterExplanationContent: (content: string) => void
  clearFilterExplanationContent: () => void
  filterExplanationContent: string | null
}
export function ContentFilterProvider({children}: {children: React.ReactNode}) {
  const [filterExplanationContent, setFilterExplanationContent] = useState<string | null>(null)
  const [filteredCategories, setFilteredCategories] = useState<Array<{category: string; severity: string}> | undefined>(
    undefined,
  )
  const [isFilteredModalOpen, setIsFilteredModalOpen] = useState(false)

  const updateFilterExplanationContent = (content: string) => {
    setFilterExplanationContent(prev => (prev || '') + content)
  }

  const clearFilterExplanationContent = () => {
    setFilterExplanationContent(null)
  }

  const value = useMemo(
    () => ({
      filteredCategories,
      setFilteredCategories,
      isFilteredModalOpen,
      setIsFilteredModalOpen,
      filterExplanationContent,
      updateFilterExplanationContent,
      clearFilterExplanationContent,
    }),
    [filterExplanationContent, filteredCategories, isFilteredModalOpen],
  )

  return <ContentFilterContext.Provider value={value}>{children}</ContentFilterContext.Provider>
}

export const ContentFilterContext = createContext<ContentFilterContext | undefined>(undefined)

export function useContentFilter() {
  const context = useContext(ContentFilterContext)
  if (!context) {
    throw new Error('useContentFilter must be used within a ContentFilterProvider')
  }
  return context
}
