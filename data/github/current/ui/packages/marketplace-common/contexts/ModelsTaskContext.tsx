import {createContext, type PropsWithChildren, useContext, useMemo, useState} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'
import {useSearchResults} from './SearchResultsContext'
import {getDefaultTask} from '../utilities/model-filter-options'

interface ModelsTaskContextType {
  task: string | null
  setTask: (task: string | null) => void
}

const ModelsTaskContext = createContext<ModelsTaskContextType | undefined>(undefined)

export function useModelsTask() {
  const context = useContext(ModelsTaskContext)
  if (!context) throw new Error('useModelsTask must be used within a ModelsTaskProvider')
  return context
}

export function ModelsTaskProvider({children}: PropsWithChildren) {
  const [searchParams] = useSearchParams()
  const {searchResults} = useSearchResults()
  const initialTask = useMemo(() => {
    if (searchParams.get('type') === 'models') return getDefaultTask(searchParams, searchResults.parsedQuery)
    return null
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const [task, setTask] = useState<string | null>(initialTask)
  const value = useMemo(() => ({task, setTask}), [task, setTask])
  return <ModelsTaskContext.Provider value={value}>{children}</ModelsTaskContext.Provider>
}
