import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'

interface SearchTypeContextType {
  type: string | null
  setType: (type: string | null) => void
}

const SearchTypeContext = createContext<SearchTypeContextType | undefined>(undefined)

export function useSearchType() {
  const context = useContext(SearchTypeContext)
  if (!context) throw new Error('useSearchType must be used within a SearchTypeProvider')
  return context
}

export function SearchTypeProvider({children}: PropsWithChildren) {
  const [searchParams] = useSearchParams()
  const [type, setType] = useState<string | null>(() => searchParams.get('type'))
  const value = useMemo(() => ({type, setType}), [type, setType])
  return <SearchTypeContext.Provider value={value}>{children}</SearchTypeContext.Provider>
}
