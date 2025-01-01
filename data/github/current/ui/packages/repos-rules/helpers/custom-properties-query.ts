import {tokenizeQuery} from '@github-ui/repos-picker'
import type {PropertyConfiguration, RepositoryPropertyParameters} from '../types/rules-types'

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

export function queryToPropertyParameters(query: string): RepositoryPropertyParameters {
  const tokens = tokenizeQuery(query)

  const include: PropertyConfiguration[] = []
  const exclude: PropertyConfiguration[] = []

  for (const token of tokens) {
    if (token.type === 'text') {
      continue
    }

    const isNegation = token.key.startsWith('-')
    const name = token.key.replace('-', '')

    if (!isSupportedKey(name)) {
      continue
    }

    const property: PropertyConfiguration = {
      name: dropPropertyPrefix(name),
      source: isCustomPropertiesKey(name) ? 'custom' : 'system',
      property_values: token.values.map(dropWrappingQuotes),
    }

    if (isNegation) {
      exclude.push(property)
    } else {
      include.push(property)
    }
  }

  return {include, exclude}
}

function isSupportedKey(key: string) {
  return isCustomPropertiesKey(key) || ['language', 'fork', 'visibility'].includes(key)
}

function isCustomPropertiesKey(key: string) {
  return key.startsWith('properties.') || key.startsWith('props.') || key.startsWith('p.')
}

function dropWrappingQuotes(value: string) {
  if (value.startsWith('"') && value.endsWith('"')) {
    return value.slice(1, -1)
  }
  return value
}

function dropPropertyPrefix(key: string) {
  if (isCustomPropertiesKey(key)) {
    const [, ...segments] = key.split('.')
    const name = segments.join('.')
    return `${name}`
  }

  return key
}
