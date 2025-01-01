// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {render, screen, waitFor} from '@testing-library/react'

import {Filter} from '../../Filter'
import {RepositoryFilterProvider} from '../../providers'
import {updateFilterValue} from '../../test-utils'
import {
  appendToFilterAndRenderAsyncSuggestions,
  expectFilterValueToBe,
  expectSuggestionsToMatchSnapshot,
  selectSuggestion,
  setupAsyncErrorHandler,
  setupRepositoriesMockApi,
} from '../utils/helpers'

describe('Repository', () => {
  setupAsyncErrorHandler()
  setupRepositoriesMockApi()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new RepositoryFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('repo:react')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('primer/react')

    await expectFilterValueToBe('repo:primer/react')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new RepositoryFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('reeeact')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })

  it('should filter and select suggestions when added in the start of multiple values', async () => {
    const filterProviders = [new RepositoryFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:issue repo:,primer/react text')

    await appendToFilterAndRenderAsyncSuggestions('react', 'is:issue repo:'.length)

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('facebook/react')

    await expectFilterValueToBe('is:issue repo:facebook/react,primer/react text')
  })
})
