import memoize from '@github/memoize'
import {reportTraceData} from '@github-ui/internal-api-insights'
import {buildProjectKey, buildRepositoryKey, buildTeamKey, getPageViewsMap} from './page-views'

const MAX_PAGE_VIEWS_TO_SEND_TO_SERVER = 10

export type Suggestion = {
  avatarUrl: string | null
  databaseId: number
  name: string
  number: number | null
  owner: {name: string; __typename: string} | null
  path: string
  rank: number
  type: 'Project' | 'Repository' | 'Team'
  pageKey: string
}

type ErrorResponse = {
  data: {
    errors: unknown[]
  }
}
type SuccessResponse = {
  data: {
    suggestions: {
      nodes: Array<Suggestion | null>
    }
  }
}
export type SuggestionsResponse = ErrorResponse | SuccessResponse

export function getSuggestionsRequestData(maxPageViews: number): FormData {
  const data = new FormData()
  for (const pageKey of Object.keys(getPageViewsMap()).slice(0, maxPageViews)) {
    data.append('variables[pageViews][]', pageKey)
  }

  return data
}

export function parseSuggestionsResponse(response: SuggestionsResponse): Suggestion[] {
  if ('errors' in response.data) return []

  let i = 1
  const suggestions = []
  for (const suggestion of response.data.suggestions.nodes) {
    if (suggestion == null) continue
    // Fill in the rank as reported by the server.
    suggestion.rank = i++
    suggestion.pageKey = pageKeyFromSuggestion(suggestion)
    if (suggestion.type === 'Team') {
      suggestion.name = `@${suggestion.name}`
    }
    suggestions.push(suggestion)
  }

  return suggestions
}

export function buildSearchURL(searchPath: string, queryText: string): string {
  const url = new URL(searchPath, window.location.origin)
  const searchParams = new URLSearchParams(url.search.slice(1))

  searchParams.set('q', queryText)

  // persist the "type" of the search results page if there is one
  const searchType = new URLSearchParams(window.location.search).get('type')
  if (searchType) {
    searchParams.set('type', searchType)
  }

  url.search = searchParams.toString()
  return url.toString()
}

export function updateSearchURL(queryText: string, href: string): string {
  const url = new URL(href, window.location.origin)
  const searchParams = new URLSearchParams(url.search.slice(1))

  if (searchParams.get('q')) {
    searchParams.set('q', queryText)
  }

  url.search = searchParams.toString()
  return url.toString()
}

function pageKeyFromSuggestion(suggestion: Suggestion): string {
  let key: string
  const [ownerLogin, repositoryName] = suggestion.name.split('/') || []
  switch (suggestion.type) {
    case 'Project':
      if (!suggestion.owner) throw new Error('Project owner is required')
      key = buildProjectKey(suggestion.owner.name, `${suggestion.number}`)
      break
    case 'Repository':
      if (!ownerLogin || !repositoryName) throw new Error('Repository owner and name are required')
      key = buildRepositoryKey(ownerLogin, repositoryName)
      break
    case 'Team':
      if (!ownerLogin || !repositoryName) throw new Error('Team owner and name are required')
      key = buildTeamKey(ownerLogin, repositoryName)
      break
    default:
      throw new Error(`Invalid Suggestion type: ${suggestion.type}`)
  }
  return key
}

const suggestionsCache = new Map()
export function clearSuggestionsCache() {
  suggestionsCache.clear()
}

async function fetchSuggestions(url: string, token: string): Promise<Suggestion[]> {
  const data = getSuggestionsRequestData(MAX_PAGE_VIEWS_TO_SEND_TO_SERVER)
  data.set('_method', 'GET') // Allow this request to be treated as a GET and query DB replica

  let result: Suggestion[] = []

  const fetchUrl = new URL(url, window.location.origin)

  if (location.search.match(/_tracing=true/)) {
    fetchUrl.searchParams.set('graphql_query_trace', 'true')
  }

  const response = await fetch(fetchUrl.href, {
    method: 'POST',
    mode: 'same-origin',
    body: data,
    headers: {
      Accept: 'application/json',
      'Scoped-CSRF-Token': token,
      'X-Requested-With': 'XMLHttpRequest',
    },
  })

  if (response.ok) {
    const jsonResponse = await response.json()
    reportTraceData(jsonResponse)
    result = parseSuggestionsResponse(jsonResponse)
  }

  // Hack to inject custom commands
  const hiddenSearchCommandsInput = document.querySelector('.js-search-commands')
  if (hiddenSearchCommandsInput instanceof HTMLInputElement) {
    const jsonString = hiddenSearchCommandsInput.value
    let parsedSearchCommands = []
    try {
      parsedSearchCommands = JSON.parse(jsonString).commands
    } catch {
      // noop
    }
    result = result.concat(parsedSearchCommands)
  }

  return result
}

let fetchSuggestionsLastUsedAt = 0
const memoizedFetchSuggestions = memoize(fetchSuggestions, {cache: suggestionsCache})

// Fetch entire list of possible suggestions from the server.
export async function getSuggestions(field: HTMLElement): Promise<Suggestion[]> {
  const url = field.getAttribute('data-jump-to-suggestions-path')
  if (!url) throw new Error('could not get jump to suggestions path')
  const token = findNextElementSibling(field, 'js-data-jump-to-suggestions-path-csrf') as HTMLInputElement
  if (!token) return []

  // We don't want to fetch the same results more than once, but we also don't want to use stale results, so we forget the whole cache after 5 sec.
  // Expiring each entry separately would be overkill for this simple case
  if (Date.now() - fetchSuggestionsLastUsedAt > 5000) {
    clearSuggestionsCache()
  }
  fetchSuggestionsLastUsedAt = Date.now()
  return memoizedFetchSuggestions(url, token.value)
}

export default function findNextElementSibling(element: HTMLElement, className: string): HTMLElement | null {
  const nextSibling = element.nextElementSibling
  if (nextSibling instanceof HTMLElement) {
    if (nextSibling.classList.contains(className)) return nextSibling
    return findNextElementSibling(nextSibling, className)
  }
  return null
}
