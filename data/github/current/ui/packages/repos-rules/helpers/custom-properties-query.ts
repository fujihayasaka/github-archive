import {dropWrappingQuotes, pruneQuery} from '@github-ui/filter-query'
import {isCustomPropertiesKey} from '@github-ui/repos-filter/providers'
import type {PropertyConfiguration, RepositoryPropertyParameters} from '../types/rules-types'
import type {SuppliedFilterProvider} from '@github-ui/filter'

export function buildQueryForProperty(property: PropertyConfiguration, negationPrefix: string): string {
  const valueString = property.property_values.map(quoteIfNeeded).join(',')
  const propPrefix = property.source === 'system' ? '' : 'props.'
  return `${negationPrefix}${propPrefix}${property.name}:${valueString}`
}

const specialCharactersPattern = new RegExp(/[ ()',]/)
function quoteIfNeeded(value: string) {
  return specialCharactersPattern.test(value) ? `"${value}"` : value
}

export function buildQueryForAllProperties(properties: RepositoryPropertyParameters): string {
  const includeParts = properties.include.map(property => buildQueryForProperty(property, ''))
  const excludeParts = properties.exclude.map(property => buildQueryForProperty(property, '-'))

  return [...includeParts, ...excludeParts].join(' ')
}

// Remove the removeDupNonMultiKeys parameter when the feature flag ruleset_allow_dup_multi_select_props is removed
export function queryToPropertyParameters(
  query: string,
  providers: SuppliedFilterProvider[],
  removeDupNonMultiKeys: boolean = false,
): RepositoryPropertyParameters {
  const validTokens = pruneQuery(query, providers, removeDupNonMultiKeys)

  const include: PropertyConfiguration[] = []
  const exclude: PropertyConfiguration[] = []

  for (const token of validTokens) {
    if (token.type === 'text') {
      continue
    }

    const property: PropertyConfiguration = {
      name: dropPropertyPrefix(token.key),
      source: isCustomPropertiesKey(token.key) ? 'custom' : 'system',
      property_values: token.values.map(dropWrappingQuotes),
    }

    if (token.isNegated) {
      exclude.push(property)
    } else {
      include.push(property)
    }
  }

  return {include, exclude}
}

function dropPropertyPrefix(key: string) {
  if (isCustomPropertiesKey(key)) {
    const [, ...segments] = key.split('.')
    const name = segments.join('.')
    return `${name}`
  }

  return key
}
