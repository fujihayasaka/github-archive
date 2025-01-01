import {createContext, useContext, useEffect, useMemo, useState, useCallback, useRef} from 'react'
import {useSearchParams} from '@github-ui/use-navigate'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {SearchResults} from '../types'
import {
  allPublishersOption,
  allTasksOptionID,
  getValidPublisherFromParsedQuery,
  getValidCategoryFromParsedQuery as getValidModelsCategoryFromParsedQuery,
  getValidSortFromParsedQuery as getValidModelsSortFromParsedQuery,
  getValidTaskFromParsedQuery,
} from '../utilities/model-filter-options'
import {useSearchResults} from './SearchResultsContext'
import {useSort} from './SortContext'
import {useFeaturedListings} from './FeaturedListingsContext'
import {useRecommendedListings} from './RecommendedListingsContext'
import {useRecentlyAddedListings} from './RecentlyAddedListingsContext'
import {useCreators} from './CreatorsContext'
import {useCategory} from './CategoryContext'
import {useSearchType} from './SearchTypeContext'
import {useCopilotApp} from './CopilotAppContext'
import {useModelsTask} from './ModelsTaskContext'
import {useModelsPublisher} from './ModelsPublisherContext'

export interface FilterContextType {
  loading: boolean
  query: string
  legacyOnQueryChange: (query: string) => void
  onQueryChange: (query: string, newType: string | null) => void
  onParsedQueryChange: (parsedQuery: SearchResults['parsedQuery']) => void
  page: number
  setPage: (page: number) => void
  filter: string
  setFilter: (filter: string) => void
  isSearching: boolean
}
const filterOptions = {
  all: 'All',
  free_trial: 'Free trial',
}
export const FilterContext = createContext<FilterContextType>({
  loading: false,
  query: '',
  legacyOnQueryChange: () => undefined,
  onQueryChange: () => undefined,
  onParsedQueryChange: () => undefined,
  page: 1,
  setPage: () => undefined,
  filter: filterOptions.all,
  setFilter: () => undefined,
  isSearching: false,
})
export function useFilterContext() {
  return useContext(FilterContext)
}
export function FilterProvider({children}: {children: React.ReactNode}) {
  const firstUpdate = useRef(true)
  const {setFeatured} = useFeaturedListings()
  const {setRecommended} = useRecommendedListings()
  const {setRecentlyAdded} = useRecentlyAddedListings()
  const {searchResults, setSearchResults} = useSearchResults()
  const {resetSort, sort, setSort, isDefaultSort} = useSort()
  const {creators, setCreators} = useCreators()
  const [loading, setLoading] = useState(false)
  const [searchParams] = useSearchParams()
  const queryWithoutSort = useMemo(() => {
    const queryString = searchParams.get('query')
    if (!queryString) {
      return ''
    }
    return queryString.replace(/sort:([^ ]*)/, '').trim()
  }, [searchParams])
  const [query, setQuery] = useState(queryWithoutSort || '')

  const defaultPage = useMemo(() => {
    if (searchParams.has('page')) {
      const page = Number(searchParams.get('page'))
      return page
    } else {
      return 1
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const [page, setPage] = useState(defaultPage)

  const defaultFilter = useMemo(() => {
    if (searchParams.has('filter')) {
      const filter = searchParams.get('filter')
      if (filter === 'free_trial') {
        return filterOptions.free_trial
      }
    }
    return filterOptions.all
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const [filter, setFilter] = useState(defaultFilter)

  const {type, setType} = useSearchType()
  const {category, setCategory} = useCategory()
  const {task, setTask} = useModelsTask()
  const {publisher, setPublisher} = useModelsPublisher()
  const {copilotApp, setCopilotApp} = useCopilotApp()

  const onModelsQueryChange = useCallback(() => {
    setTask(allTasksOptionID)
    setPublisher(allPublishersOption)
  }, [setPublisher, setTask])

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
    [onModelsQueryChange, resetSort, setCategory, setCopilotApp, setCreators, setType, type],
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
    [onModelsQueryChange, resetSort, setCreators],
  )

  const shouldDisplaySearchResults = useMemo(() => {
    return !!(query || category || type || copilotApp)
  }, [category, copilotApp, query, type])
  const [isSearching, setIsSearching] = useState(shouldDisplaySearchResults)

  const onModelsParsedQueryChange = useCallback(
    (parsedQuery: SearchResults['parsedQuery']) => {
      const categoryFromParsedQuery = getValidModelsCategoryFromParsedQuery(parsedQuery)
      if (categoryFromParsedQuery) setCategory(categoryFromParsedQuery)

      const taskFromParsedQuery = getValidTaskFromParsedQuery(parsedQuery)
      if (taskFromParsedQuery) setTask(taskFromParsedQuery)

      const publisherFromParsedQuery = getValidPublisherFromParsedQuery(parsedQuery)
      if (publisherFromParsedQuery) setPublisher(publisherFromParsedQuery)

      const sortFromParsedQuery = getValidModelsSortFromParsedQuery(parsedQuery)
      if (sortFromParsedQuery) setSort(sortFromParsedQuery)
    },
    [setCategory, setPublisher, setSort, setTask],
  )

  const onParsedQueryChange = useCallback(
    (parsedQuery: SearchResults['parsedQuery']) => {
      if (type === 'models') onModelsParsedQueryChange(parsedQuery)
    },
    [onModelsParsedQueryChange, type],
  )

  const parsedQueryStr = searchResults.parsedQuery ? JSON.stringify(searchResults.parsedQuery) : ''
  const fetchSearchResults = useCallback(
    async (path: string) => {
      setLoading(true)
      const response = await verifiedFetchJSON(path)
      const data = await response.json()
      let newParsedQuery: SearchResults['parsedQuery']
      if (shouldDisplaySearchResults) {
        newParsedQuery = data.parsedQuery
        // This will be just search results
        setSearchResults(data)
      } else {
        // This will be the full index payload
        setFeatured(data.featured)
        setRecommended(data.recommended)
        setRecentlyAdded(data.recentlyAdded)
        const newSearchResults = data.searchResults ?? data.results
        newParsedQuery = newSearchResults?.parsedQuery
        setSearchResults(newSearchResults)
      }
      if (newParsedQuery && parsedQueryStr !== JSON.stringify(newParsedQuery)) onParsedQueryChange(newParsedQuery)
      setIsSearching(shouldDisplaySearchResults)
      setLoading(false)
    },
    [
      parsedQueryStr,
      onParsedQueryChange,
      setFeatured,
      setRecentlyAdded,
      setRecommended,
      setSearchResults,
      shouldDisplaySearchResults,
    ],
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
    window.history.replaceState({}, '', path)
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
      query,
      legacyOnQueryChange,
      onQueryChange,
      onParsedQueryChange,
      page,
      setPage,
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
    query,
    legacyOnQueryChange,
    onQueryChange,
    onParsedQueryChange,
    page,
    setPage,
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
