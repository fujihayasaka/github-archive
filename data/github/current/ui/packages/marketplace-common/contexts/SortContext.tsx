import {createContext, type PropsWithChildren, useCallback, useContext, useMemo, useState} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'
import {
  defaultSortValue as modelsDefaultSortValue,
  getDefaultSort as getModelsDefaultSort,
} from '../utilities/model-filter-options'
import {useSearchResults} from './SearchResultsContext'
import {filterRegexForQueryString} from '../utilities/filters'

interface SortContextType {
  resetSort: () => void
  sort: string
  setSort: (sort: string) => void
  isDefaultSort: boolean
}

// Keep in sync with MarketplaceHelper::DEFAULT_SORT_VALUE in Ruby.
const defaultSortValue = 'popularity-desc'

const SortContext = createContext<SortContextType | undefined>(undefined)

export function useSort() {
  const context = useContext(SortContext)
  if (!context) throw new Error('useSort must be used within a SortProvider')
  return context
}

export function SortProvider({children}: PropsWithChildren) {
  const [searchParams] = useSearchParams()
  const {
    searchResults: {parsedQuery},
  } = useSearchResults()
  const initialSort = useMemo(() => {
    const queryFromParams = searchParams.get('query')
    let sortValue: string | undefined
    if (queryFromParams) {
      const match = queryFromParams.match(filterRegexForQueryString('sort'))
      sortValue = match ? match[1] : undefined
    }

    if (searchParams.get('type') === 'models') return getModelsDefaultSort(sortValue, parsedQuery)

    switch (sortValue) {
      case 'created-desc':
        return 'created-desc'
      case 'match-desc':
        return 'match-desc'
      default:
        return defaultSortValue
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const [sort, setSort] = useState(initialSort)

  const defaultSortValueForType = searchParams.get('type') === 'models' ? modelsDefaultSortValue : defaultSortValue
  const resetSort = useCallback(() => setSort(defaultSortValueForType), [defaultSortValueForType])

  const value = useMemo(
    () => ({sort, isDefaultSort: sort === defaultSortValueForType, resetSort, setSort}),
    [defaultSortValueForType, sort, resetSort, setSort],
  )
  return <SortContext.Provider value={value}>{children}</SortContext.Provider>
}
