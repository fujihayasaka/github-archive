import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {IndexPayload, SearchResults} from '../types'

interface SearchResultsContextType {
  searchResults: SearchResults
  setSearchResults: (searchResults: SearchResults) => void
}

const SearchResultsContext = createContext<SearchResultsContextType | undefined>(undefined)

export function useSearchResults() {
  const context = useContext(SearchResultsContext)
  if (!context) throw new Error('useSearchResults must be used within a SearchResultsProvider')
  return context
}

export function SearchResultsProvider({children}: PropsWithChildren) {
  const {searchResults: initialSearchResults} = useRoutePayload<IndexPayload>()
  const [searchResults, setSearchResults] = useState<SearchResults>(initialSearchResults)
  const value = useMemo(() => ({searchResults, setSearchResults}), [searchResults, setSearchResults])
  return <SearchResultsContext.Provider value={value}>{children}</SearchResultsContext.Provider>
}
