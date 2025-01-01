import {type FilterProvider, FilterProviderType} from '@github-ui/filter'
import {FilterQueryParser} from '@github-ui/filter/parser'
import {MoonIcon} from '@primer/octicons-react'

import type {QuerySegment} from './types'

const keyPattern = new RegExp(/([\w.-]+):/g)
export function tokenizeQuery(query: string): QuerySegment[] {
  if (query.length > 1000) {
    // If the query is too long, avoid parsing to prevent a DoS attack. - rule `js/polynomial-redos`
    return [
      {
        type: 'text',
        value: query,
      },
    ]
  }

  // Identify potential keys to create providers needed for parsing
  const keys = Array.from(query.matchAll(keyPattern), match => match[1] || '').filter(Boolean)
  const providers = keys.map(buildFakeProvider)

  const parser = new FilterQueryParser(providers)

  return parser
    .parse(query)
    .blocks.filter(block => block.type !== 'space')
    .map<QuerySegment>(block => {
      if (block.type === 'filter') {
        const isNegated = block.key.value.startsWith('-')
        const key = isNegated ? block.key.value.slice(1) : block.key.value

        return {
          type: 'filter',
          key,
          isNegated,
          values: block.value.values.map(({value}) => `${value}`),
          raw: block.raw,
        }
      } else {
        return {type: 'text', value: block.raw}
      }
    })
}

function buildFakeProvider(key: string): FilterProvider {
  return {
    key,
    icon: MoonIcon,
    priority: 0,
    getSuggestions: () => null,
    type: FilterProviderType.Text,
    validateFilterBlockValues: (_filterQuery, _block, values) => values,
    getValueRowProps: () => ({text: ''}),
    options: {
      priority: 0,
      filterTypes: {},
      support: {},
    },
  }
}
