import type {FilterProvider, SuppliedFilterProvider} from '@github-ui/filter'
import {NestedFilterProvider} from '@github-ui/filter/providers'

import {tokenizeQuery} from './tokenize-query'
import type {QuerySegment} from './types'

/**
 * Get every segment in the query that is not a valid key based on the providers.
 */
export function validateQueryKeys(query: string, providers?: SuppliedFilterProvider[]): QuerySegment[] {
  if (!providers) return []

  const keysMap = getProvidersMap(providers)

  const isInvalidKey = (segment: QuerySegment) => segment.type === 'text' || !keysMap.has(segment.key)

  return tokenizeQuery(query).filter(isInvalidKey)
}

/**
 * Returns a clean query without any invalid segments. Free-text segments are removed too.
 */
// Remove the removeDupNonMultiKeys parameter when the feature flag ruleset_allow_dup_multi_select_props is removed
export function pruneQuery(
  query: string,
  providers: SuppliedFilterProvider[],
  removeDupNonMultiKeys?: boolean,
): QuerySegment[] {
  const keysMap = getProvidersMap(providers)

  const isValidKey = (segment: QuerySegment) => segment.type !== 'text' && keysMap.has(segment.key)
  const isValidValue = (segment: QuerySegment) =>
    segment.type !== 'text' && areAllValuesInProvider(segment, keysMap.get(segment.key))

  const validTokens = tokenizeQuery(query).filter(isValidKey).filter(isValidValue)

  return dedupNonMultiKeys(validTokens, keysMap, removeDupNonMultiKeys)
}

function dedupNonMultiKeys(
  segments: QuerySegment[],
  keysMap: Map<string, FilterProvider>,
  removeDupNonMultiKeys?: boolean,
): QuerySegment[] {
  const uniqueKeys = new Set<string>()
  const dedupTokens: QuerySegment[] = []

  for (const token of segments) {
    if (token.type === 'text') {
      dedupTokens.push(token)
    } else {
      const provider = keysMap.get(token.key)
      const isMultiKey = !provider || provider.options.filterTypes.multiKey
      const segmentHash = removeDupNonMultiKeys ? token.key : `${token.key}#${token.isNegated}`
      if (isMultiKey || !uniqueKeys.has(segmentHash)) {
        uniqueKeys.add(segmentHash)
        dedupTokens.push(token)
      }
    }
  }

  return dedupTokens
}

function areAllValuesInProvider(segment: QuerySegment, provider?: FilterProvider): boolean {
  if (segment.type === 'text') return false

  const filterValues = provider?.filterValues || []
  if (filterValues.length === 0) return true

  return segment.values
    .map(dropWrappingQuotes)
    .every(v => filterValues.find(fv => (fv.value as string).toLowerCase() === v.toLowerCase()))
}

function getProvidersMap(providers: SuppliedFilterProvider[]): Map<string, FilterProvider> {
  const keysMap = new Map<string, FilterProvider>()
  for (const provider of flattenProviders(providers)) {
    keysMap.set(provider.key, provider)
    for (const alias of provider.aliases || []) {
      keysMap.set(alias, provider)
    }
  }
  return keysMap
}

function flattenProviders(providers: SuppliedFilterProvider[]): FilterProvider[] {
  const flattenedProviders: FilterProvider[] = []
  for (const provider of providers) {
    if (provider instanceof NestedFilterProvider) {
      flattenedProviders.push(...provider.filterProviders)
    } else {
      flattenedProviders.push(provider)
    }
  }

  return flattenedProviders
}

/**
 * Removes the wrapping quotes from a value if it starts and ends with quotes.
 */
export function dropWrappingQuotes(value: string) {
  if (value.startsWith('"') && value.endsWith('"')) {
    return value.slice(1, -1)
  }
  return value
}
