import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'
import {useSearchResults} from './SearchResultsContext'
import {getDefaultPublisher} from '../utilities/model-filter-options'

interface ModelsPublisherContextType {
  publisher: string | null
  setPublisher: (publisher: string | null) => void
}

const ModelsPublisherContext = createContext<ModelsPublisherContextType | undefined>(undefined)

export function useModelsPublisher() {
  const context = useContext(ModelsPublisherContext)
  if (!context) throw new Error('useModelsPublisher must be used within a ModelsPublisherProvider')
  return context
}

export function ModelsPublisherProvider({children}: PropsWithChildren) {
  const [searchParams] = useSearchParams()
  const {searchResults} = useSearchResults()
  const initialPublisher = useMemo(() => {
    if (searchParams.get('type') === 'models') return getDefaultPublisher(searchParams, searchResults.parsedQuery)
    return null
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const [publisher, setPublisher] = useState<string | null>(initialPublisher)
  const value = useMemo(
    () => ({publisher, setPublisher}) satisfies ModelsPublisherContextType,
    [publisher, setPublisher],
  )
  return <ModelsPublisherContext.Provider value={value}>{children}</ModelsPublisherContext.Provider>
}
