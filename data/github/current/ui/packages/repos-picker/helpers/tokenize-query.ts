import {type FilterProvider, FilterProviderType} from '@github-ui/filter'
import {FilterQueryParser} from '@github-ui/filter/parser'
import {MoonIcon} from '@primer/octicons-react'

export interface FilterQuerySegment {
  type: 'filter'
  key: string
  values: string[]
  raw: string
}

interface TextQuerySegment {
  type: 'text'
  value: string
}
type QuerySegment = FilterQuerySegment | TextQuerySegment

const keyPattern = new RegExp(/([\w.-]+):/g)
export function tokenizeQuery(query: string): QuerySegment[] {
  // Identify potential keys to create providers needed for parsing
  const keys = Array.from(query.matchAll(keyPattern), match => match[1] || '').filter(Boolean)
  const providers = keys.map(buildFakeProvider)

  const parser = new FilterQueryParser(providers)

  return parser
    .parse(query)
    .blocks.filter(block => block.type !== 'space')
    .map<QuerySegment>(block => {
      if (block.type === 'filter') {
        return {
          type: 'filter',
          key: block.key.value,
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
