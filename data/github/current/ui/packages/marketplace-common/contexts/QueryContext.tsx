import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'

interface QueryContextType {
  query: string
  setQuery: (query: string) => void
}

const QueryContext = createContext<QueryContextType | undefined>(undefined)

export function useQuery() {
  const context = useContext(QueryContext)
  if (!context) throw new Error('useQuery must be used within a QueryProvider')
  return context
}

export function QueryProvider({children}: PropsWithChildren) {
  const [searchParams] = useSearchParams()
  const queryWithoutSort = useMemo(() => {
    const queryString = searchParams.get('query')
    return queryString ? queryString.replace(/sort:([^ ]*)/, '').trim() : ''
  }, [searchParams])
  const [query, setQuery] = useState(queryWithoutSort || '')
  const value = useMemo(() => ({query, setQuery}), [query, setQuery])
  return <QueryContext.Provider value={value}>{children}</QueryContext.Provider>
}
