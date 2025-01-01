import {useCallback, useMemo, useState} from 'react'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {SearchResults} from '../types'
import {useOnParsedQueryChange} from '../hooks/use-on-parsed-query-change'
import {useSearchResults} from '../contexts/SearchResultsContext'
import {useFeaturedListings} from '../contexts/FeaturedListingsContext'
import {useRecommendedListings} from '../contexts/RecommendedListingsContext'
import {useRecentlyAddedListings} from '../contexts/RecentlyAddedListingsContext'
import {useQuery} from '../contexts/QueryContext'
import {useCategory} from '../contexts/CategoryContext'
import {useSearchType} from '../contexts/SearchTypeContext'
import {useCopilotApp} from '../contexts/CopilotAppContext'

interface FetchSearchResults {
  isSearching: boolean
  loading: boolean
  fetchSearchResults: (path: string) => Promise<void>
}

export function useFetchSearchResults(): FetchSearchResults {
  const {searchResults, setSearchResults} = useSearchResults()
  const {setFeatured} = useFeaturedListings()
  const {setRecommended} = useRecommendedListings()
  const {setRecentlyAdded} = useRecentlyAddedListings()
  const {query} = useQuery()
  const {category} = useCategory()
  const {type} = useSearchType()
  const {copilotApp} = useCopilotApp()
  const shouldDisplaySearchResults = useMemo(() => {
    return !!(query || category || type || copilotApp)
  }, [category, copilotApp, query, type])
  const [isSearching, setIsSearching] = useState(shouldDisplaySearchResults)
  const onParsedQueryChange = useOnParsedQueryChange()
  const parsedQueryStr = searchResults.parsedQuery ? JSON.stringify(searchResults.parsedQuery) : ''
  const [loading, setLoading] = useState(false)

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

  return {fetchSearchResults, isSearching, loading}
}
