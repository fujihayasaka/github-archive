import {render, screen, waitFor} from '@testing-library/react'

import {Filter} from '../../Filter'
import {MilestoneFilterProvider} from '../../providers'
import {updateFilterValue} from '../../test-utils'
import {
  appendToFilterAndRenderAsyncSuggestions,
  expectFilterValueToBe,
  expectSuggestionsToMatchSnapshot,
  selectSuggestion,
  setupAsyncErrorHandler,
  setupMilestoneMockApi,
} from '../utils/helpers'

describe('Milestone', () => {
  setupAsyncErrorHandler()
  setupMilestoneMockApi()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new MilestoneFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('milestone:al')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('alpha')

    await expectFilterValueToBe('milestone:Alpha')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new MilestoneFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('alfalfa')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })

  it('should filter and select suggestions when added in the start of multiple values', async () => {
    const filterProviders = [new MilestoneFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:issue milestone:,foo text')

    await appendToFilterAndRenderAsyncSuggestions('alpha', 'is:issue milestone:'.length)

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('alpha')

    await expectFilterValueToBe('is:issue milestone:Alpha,foo text')
  })
})
