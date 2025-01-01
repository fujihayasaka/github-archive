import {createContext, useCallback, useContext, useEffect, useMemo, useState, useRef} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'
import {allPublishersOption, allTasksOptionID} from '../utilities/model-filter-options'
import {useSort} from './SortContext'
import {useCreators} from './CreatorsContext'
import {useCategory} from './CategoryContext'
import {useSearchType} from './SearchTypeContext'
import {useCopilotApp} from './CopilotAppContext'
import {useModelsTask} from './ModelsTaskContext'
import {useModelsPublisher} from './ModelsPublisherContext'
import {useOnModelsQueryChange} from '../hooks/use-on-models-query-change'
import {filterOptions} from '../utilities/filters'
import {usePage} from './PageContext'
import {useQuery} from './QueryContext'
import {updateUrl} from '@github-ui/history'
import {useFetchSearchResults} from '../hooks/use-fetch-search-results'

export interface FilterContextType {
  loading: boolean
  legacyOnQueryChange: (query: string) => void
  onQueryChange: (query: string, newType: string | null) => void
  filter: string
  setFilter: (filter: string) => void
  isSearching: boolean
}
export const FilterContext = createContext<FilterContextType>({
  loading: false,
  legacyOnQueryChange: () => undefined,
  onQueryChange: () => undefined,
  filter: filterOptions.all,
  setFilter: () => undefined,
  isSearching: false,
})
export function useFilterContext() {
  return useContext(FilterContext)
}
export function FilterProvider({children}: {children: React.ReactNode}) {
  const firstUpdate = useRef(true)
  const {resetSort, sort, isDefaultSort} = useSort()
  const {creators, setCreators} = useCreators()
  const [searchParams] = useSearchParams()
  const {query, setQuery} = useQuery()
  const {page, setPage} = usePage()

  const defaultFilter = useMemo(() => {
    if (searchParams.has('filter')) {
      const filter = searchParams.get('filter')
      if (filter === 'free_trial') {
        return filterOptions.free_trial
      }
    }
    return filterOptions.all
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const [filter, setFilter] = useState(defaultFilter)

  const {type, setType} = useSearchType()
  const {category, setCategory} = useCategory()
  const {task, setTask} = useModelsTask()
  const {publisher, setPublisher} = useModelsPublisher()
  const {copilotApp, setCopilotApp} = useCopilotApp()
  const onModelsQueryChange = useOnModelsQueryChange()
  const {fetchSearchResults, isSearching, loading} = useFetchSearchResults()

  const legacyOnQueryChange = useCallback(
    (qry: string) => {
      // When setting a new query, we reset all filters and sort
      setPage(1)
      setFilter(filterOptions.all)
      setCreators('All creators')
      if (type === 'models') {
        onModelsQueryChange()
      } else {
        setType(null)
      }
      resetSort()
      setCategory(null)
      setCopilotApp(null)
      setQuery(qry.trim())
    },
    [onModelsQueryChange, resetSort, setCategory, setCopilotApp, setCreators, setPage, setQuery, setType, type],
  )

  const onQueryChange = useCallback(
    (qry: string, newType: string | null) => {
      // When setting a new query, we reset all filters and sort
      setPage(1)
      setFilter(filterOptions.all)
      setCreators('All creators')
      if (newType === 'models') onModelsQueryChange()
      resetSort()
      setQuery(qry.trim())
    },
    [onModelsQueryChange, resetSort, setCreators, setPage, setQuery],
  )

  useEffect(() => {
    if (firstUpdate.current) {
      // The app is initially rendered with a payload so we don't want to run this on the first page load
      firstUpdate.current = false
      return
    }

    const newParams = new URLSearchParams()
    if (query || !isDefaultSort) {
      if (isDefaultSort) {
        newParams.set('query', query)
      } else {
        newParams.set('query', `${query} sort:${sort}`.trim())
      }
    }
    if (filter === filterOptions.free_trial) newParams.set('filter', 'free_trial')
    if (creators === 'Verified creators') newParams.set('verification', 'verified_creator')
    if (page !== 1) newParams.set('page', page.toString())
    if (category) newParams.set('category', category)
    if (publisher && publisher !== allPublishersOption) newParams.set('publisher', publisher)
    if (task && task !== allTasksOptionID) newParams.set('task', task)
    if (type) newParams.set('type', type)
    if (copilotApp) newParams.set('copilot_app', copilotApp)

    const path = newParams.toString() ? `/marketplace?${newParams.toString()}` : '/marketplace'
    updateUrl(path)
    fetchSearchResults(path)
  }, [
    fetchSearchResults,
    isDefaultSort,
    query,
    filter,
    creators,
    sort,
    page,
    category,
    type,
    publisher,
    task,
    copilotApp,
  ])

  const value = useMemo<FilterContextType>(() => {
    return {
      loading,
      legacyOnQueryChange,
      onQueryChange,
      filter,
      setFilter,
      task,
      setTask,
      publisher,
      setPublisher,
      type,
      setType,
      isSearching,
    }
  }, [
    loading,
    legacyOnQueryChange,
    onQueryChange,
    filter,
    setFilter,
    task,
    setTask,
    publisher,
    setPublisher,
    type,
    setType,
    isSearching,
  ])

  return <FilterContext.Provider value={value}>{children}</FilterContext.Provider>
}
