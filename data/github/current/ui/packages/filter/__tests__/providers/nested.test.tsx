// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {NoteIcon} from '@primer/octicons-react'
import {render} from '@testing-library/react'

import {Filter} from '../../Filter'
import {NestedFilterProvider} from '../../providers/nested'
import {updateFilterValue} from '../../test-utils'
import {
  expectFilterValueToBe,
  expectSuggestionsToMatchSnapshot,
  selectSuggestion,
  setupAsyncErrorHandler,
} from '../utils/helpers'

const setupNestedFilterProvider = () => {
  return new NestedFilterProvider({
    key: 'props',
    displayName: 'Properties',
    description: 'Filter by custom properties',
    priority: 3,
    icon: NoteIcon,
    subKeys: [
      {
        key: 'isProd',
        displayName: 'Is Production',
        type: 'boolean',
        description: 'Filter repositories by production status',
      },
      {
        key: 'environment',
        displayName: 'Environment',
        type: 'select',
        description: 'The environment the repository is in',
        values: [
          {value: 'production', displayName: 'Production', priority: 3},
          {value: 'staging', displayName: 'Staging', priority: 2},
          {value: 'development', displayName: 'Development', priority: 1},
        ],
        options: {
          priority: 10,
          support: {status: 'supported'},
          filterTypes: {
            multiKey: false,
            valueless: false,
          },
        },
      },
      {
        key: 'approvals',
        displayName: 'Approvals',
        type: 'select',
        description: 'Approvals required for the repository',
        values: [
          {value: 'qa', displayName: 'Quality Assurance', priority: 1},
          {value: 'security', displayName: 'Security', priority: 2},
          {value: 'design', displayName: 'Design', priority: 3},
          {value: 'product', displayName: 'Product', priority: 4},
          {value: 'dev', displayName: 'Development', priority: 5},
          {value: 'ops', displayName: 'Operations', priority: 6},
          {value: 'legal', displayName: 'Legal', priority: 7},
          {value: 'compliance', displayName: 'Compliance', priority: 8},
          {value: 'marketing', displayName: 'Marketing', priority: 9},
          {value: 'sales', displayName: 'Sales', priority: 10},
          {value: 'support', displayName: 'Support', priority: 11},
          {value: 'hr', displayName: 'Human Resources', priority: 12},
          {value: 'finance', displayName: 'Finance', priority: 13},
          {value: 'it', displayName: 'IT', priority: 14},
        ],
      },
      {
        key: 'tagline',
        displayName: 'Tagline',
        type: 'text',
        description: 'The tagline of the repository',
      },
    ],
  })
}

describe('Nested', () => {
  setupAsyncErrorHandler()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [setupNestedFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('props.')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Is Production')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('true')

    await expectFilterValueToBe('props.isProd:true')
  })

  it('should filter and select suggestions based on subkey name', async () => {
    const filterProviders = [setupNestedFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('isPro')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Is Production')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('false')

    await expectFilterValueToBe('props.isProd:false')
  })
})
