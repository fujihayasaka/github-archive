import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'

import {TIME_RANGE_VALUES} from '../../constants/dynamic-filter-values'
import {Filter} from '../../Filter'
import {ClosedFilterProvider, CreatedFilterProvider, MergedFilterProvider, UpdatedFilterProvider} from '../../providers'
import {updateFilterValue} from '../../test-utils'
import {
  appendToFilterAndRenderAsyncSuggestions,
  expectDateSuggestionsToMatchSnapshot,
  expectErrorMessage,
  expectFilterValueToBe,
  selectSuggestion,
  setupAsyncErrorHandler,
} from '../utils/helpers'

describe('Date', () => {
  setupAsyncErrorHandler()

  it('should render date suggestions', async () => {
    const filterProviders = [new CreatedFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('created:')

    await expectDateSuggestionsToMatchSnapshot()
  })
  it('should render dynamic value when selecting "Today"', async () => {
    const filterProviders = [new CreatedFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('created:')

    await expectDateSuggestionsToMatchSnapshot()

    await selectSuggestion('Today')

    await expectFilterValueToBe('created:@today')
  })

  it('should render dynamic value when selecting "Yesterday"', async () => {
    const filterProviders = [new CreatedFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)
    await updateFilterValue('created:')

    await expectDateSuggestionsToMatchSnapshot()

    await selectSuggestion('Yesterday')

    await expectFilterValueToBe('created:@today-1d')
  })

  it('should render dynamic value when selecting "Past 7 days"', async () => {
    const filterProviders = [new CreatedFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('created:')

    await expectDateSuggestionsToMatchSnapshot()

    await selectSuggestion('Past 7 days')

    await expectFilterValueToBe('created:>@today-1w')
  })

  it('should render dynamic value when selecting "Past 30 days"', async () => {
    const filterProviders = [new CreatedFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('created:')

    await expectDateSuggestionsToMatchSnapshot()

    await selectSuggestion('Past 30 days')

    const input = screen.getByRole('combobox')
    expect(input).toHaveValue('created:>@today-30d')
  })

  it('should render dynamic value when selecting "Past year"', async () => {
    const filterProviders = [new CreatedFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('created:')

    await expectDateSuggestionsToMatchSnapshot()

    await selectSuggestion('Past year')

    await expectFilterValueToBe('created:>@today-1y')
  })

  it('should render static value when selecting current day', async () => {
    const filterProviders = [new CreatedFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('created:')

    await expectDateSuggestionsToMatchSnapshot()

    const value = typeof TIME_RANGE_VALUES[5]?.value === 'function' ? TIME_RANGE_VALUES[5]?.value() : ''
    await selectSuggestion(TIME_RANGE_VALUES[5]?.displayName ?? '')
    await expectFilterValueToBe(`created:${value}`)
  })

  it('should filter suggestions based on "before" operator and still retain operator on selection', async () => {
    const filterProviders = [new CreatedFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('created:<')

    await expectDateSuggestionsToMatchSnapshot()

    await selectSuggestion('Yesterday')

    await expectFilterValueToBe('created:<@today-1d')
  })

  it('should not filter suggestions based on "after" operator', async () => {
    const filterProviders = [new CreatedFilterProvider()]

    const {user} = render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('created:>')

    await expectDateSuggestionsToMatchSnapshot()

    await user.keyboard('{ArrowDown>4}')
    await user.keyboard('{Enter}')

    await expectFilterValueToBe('created:>@today-30d')
  })

  it('should support between operator', async () => {
    const filterProviders = [new CreatedFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('created:')

    await selectSuggestion('Yesterday')

    await appendToFilterAndRenderAsyncSuggestions('..@today')

    await expectFilterValueToBe('created:@today-1d..@today')
  })

  it('should not support multiple between operator', async () => {
    const filterProviders = [new CreatedFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('created:')

    await selectSuggestion('Yesterday')

    await appendToFilterAndRenderAsyncSuggestions('..@today.. ')

    await expectFilterValueToBe('created:@today-1d..@today.. ')

    await expectErrorMessage('created', '@today-1d..@today..')
  })

  describe('Created', () => {
    it('should filter and select created suggestions based on name', async () => {
      const filterProviders = [new CreatedFilterProvider()]
      render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

      await updateFilterValue('created:@tod')

      await expectDateSuggestionsToMatchSnapshot()

      await selectSuggestion('Today')

      await expectFilterValueToBe('created:@today')
    })

    it('should not show any created suggestions based on invalid name', async () => {
      const filterProviders = [new CreatedFilterProvider()]
      render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

      await updateFilterValue('tttrrr')

      await waitFor(() => {
        expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
      })
    })
  })

  describe('Closed', () => {
    it('should filter and select closed suggestions based on name', async () => {
      const filterProviders = [new ClosedFilterProvider()]
      render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

      await updateFilterValue('closed:@tod')

      await expectDateSuggestionsToMatchSnapshot()

      await selectSuggestion('Today')

      await expectFilterValueToBe('closed:@today')
    })

    it('should not show any closed suggestions based on invalid name', async () => {
      const filterProviders = [new ClosedFilterProvider()]
      render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

      await updateFilterValue('tttrrr')

      await waitFor(() => {
        expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
      })
    })
  })

  describe('Merged', () => {
    it('should filter and select suggestions based on name', async () => {
      const filterProviders = [new MergedFilterProvider()]
      render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

      await updateFilterValue('merged:@tod')

      await expectDateSuggestionsToMatchSnapshot()

      await selectSuggestion('Today')

      await expectFilterValueToBe('merged:@today')
    })

    it('should not show any suggestions based on invalid name', async () => {
      const filterProviders = [new MergedFilterProvider()]
      render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

      await updateFilterValue('tttrrr')

      await waitFor(() => {
        expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
      })
    })
  })

  describe('Updated', () => {
    it('should filter and select suggestions based on name', async () => {
      const filterProviders = [new UpdatedFilterProvider()]
      render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

      await updateFilterValue('updated:@tod')

      await expectDateSuggestionsToMatchSnapshot()

      await selectSuggestion('Today')

      await expectFilterValueToBe('updated:@today')
    })

    it('should not show any suggestions based on invalid name', async () => {
      const filterProviders = [new UpdatedFilterProvider()]
      render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

      await updateFilterValue('tttrrr')

      await waitFor(() => {
        expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
      })
    })
  })
})
