import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'

interface PageContextType {
  page: number
  setPage: (page: number) => void
}

const PageContext = createContext<PageContextType | undefined>(undefined)

export function usePage() {
  const context = useContext(PageContext)
  if (!context) throw new Error('usePage must be used within a PageProvider')
  return context
}

export function PageProvider({children}: PropsWithChildren) {
  const [searchParams] = useSearchParams()
  const initialPage = useMemo(() => {
    return searchParams.has('page') ? Number(searchParams.get('page')) : 1
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const [page, setPage] = useState(initialPage)
  const value = useMemo(() => ({page, setPage}), [page, setPage])
  return <PageContext.Provider value={value}>{children}</PageContext.Provider>
}
