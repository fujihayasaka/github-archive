import type {SearchResults} from '../types'

export function filterStringFromQuery(
  type: string | null,
  copilotApp: string | null,
  query: string | null,
  category: string | null,
): string {
  const typeValue = copilotApp ? 'copilot' : type
  const filters = []
  if (typeValue) filters.push(buildQueryFilter('type', typeValue))
  if (category) filters.push(buildQueryFilter('category', category))

  // check if last word is filter
  const lastWord = query?.split(' ').pop()
  if (lastWord && lastWord.includes(':')) {
    // if so, add a space
    query += ' '
  }

  // return type:{type} if type is found, type:copilot if copilotApp is found or empty string if neither,
  // then append the query if found
  return `${filters.join(' ')} ${query ?? ''}`.trimStart()
}

type MarketplaceQuery = {
  type: string | null
  copilotApp: string | null
  query: string | null
  category: string | null
}

export function queryFromFilterString(filterString: string): MarketplaceQuery {
  const typeMatch = filterString.match(filterRegexForQueryString('type'))

  const result: MarketplaceQuery = {
    type: typeMatch?.[1] || null,
    copilotApp: null,
    query: filterString,
    category: null,
  }

  if (result.type) {
    result.query = removeFilterFromQuery('type', result.query)
    const categoryMatch = filterString.match(filterRegexForQueryString('category'))

    if (result.type === 'copilot') {
      result.copilotApp = 'true'
      result.type = 'apps'
    } else if (categoryMatch) {
      result.category = categoryMatch[1] || null
      result.query = removeFilterFromQuery('category', result.query)
    }
  }

  return result
}

function getFilterValuesFromParsedQuery(filter: string, parsedQuery: SearchResults['parsedQuery']): string[] {
  if (!parsedQuery) return []
  const matches = parsedQuery.filter(chunk => Array.isArray(chunk) && chunk[0] === filter)

  // Example: when filter=provider and parsedQuery is ['some search text', ['provider', 'meta']],
  // return: 'meta'
  // Example: when filter=category and parsedQuery is [['category', 'rag'], ['category', 'agents']],
  // return: ['rag', 'agents']
  // Example: when filter=category and parsedQuery is [['category', ['conversation', 'agents']]],
  // return: ['conversation', 'agents']
  let result: string[] = []
  for (const match of matches) {
    const [, value] = match
    if (Array.isArray(value)) {
      result = result.concat(value)
    } else {
      result.push(value)
    }
  }
  return result
}

/**
 * Match an ElasticSearch filter in a query string, e.g., `publisher:Meta` or `category:"large context"`.
 * @param filter the name of the search qualifier, e.g., 'sort' or 'category'
 * @returns a regex to match the specified search filter in a given query string, with groups for its value and
 * chunks within the value
 */
export function filterRegexForQueryString(filter: string) {
  return new RegExp(`${filter}:("([^"]+)"|\\S+)\\s?`)
}

function buildQueryFilter(filter: string, value: string) {
  const suffix = value.includes(' ') ? `"${value}"` : value
  return `${filter}:${suffix}`
}

export function getValidCaseInsensitiveOption(option: string | null | undefined, validOptions: string[]) {
  if (!option) return
  const normalizedValidOptions = validOptions.map(val => val.toLowerCase())
  const optionIndex = normalizedValidOptions.indexOf(option.toLowerCase())
  if (optionIndex >= 0) return validOptions[optionIndex]!
}

export function removeFilterFromQuery(filter: string, query: string | null) {
  if (!query) return ''
  if (query.trim().length < 1) return query

  const regex = filterRegexForQueryString(filter)

  let result = query
  let match = result.match(regex)
  while (match) {
    const index = match.index!
    result = result.slice(0, index) + result.slice(index + match[0].length)
    match = result.match(regex)
  }

  return result.trim()
}

/**
 * Get the valid/allowed value for a search filter from a query string, if the filter is in use.
 * @param filter the name of the search qualifier, e.g., 'provider' or 'category'
 * @param parsedQuery the parsed query list, e.g., `['foo', ['provider', 'meta'], ['sort', 'created-desc']]`
 * @param validOptions the supported values for a keyword-style search filter, e.g., `['Meta', 'AI21 Labs']`
 * @returns the value of the specified search filter in the given query string
 */
export function getValidFilterValueFromParsedQuery(
  filter: string,
  parsedQuery: SearchResults['parsedQuery'],
  validOptions: string[],
): string | undefined {
  const filterValues = getFilterValuesFromParsedQuery(filter, parsedQuery)

  for (const value of filterValues) {
    const validValue = getValidCaseInsensitiveOption(value, validOptions)
    if (validValue) return validValue
  }
}
