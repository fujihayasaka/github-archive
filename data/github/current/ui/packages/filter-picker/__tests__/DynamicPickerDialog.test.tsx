import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {render} from '@github-ui/react-core/test-utils'
import {act, screen} from '@testing-library/react'

import {DynamicPickerDialog, getDynamicResultsAnnouncement, getFiltersInvalidMessage} from '../DynamicPickerDialog'
import {fruitItemConfig, sampleFruits} from '../test-utils/mock-data'

const defaultProps = {
  query: '',
  onSubmit: jest.fn(),
  onDismiss: jest.fn(),
  returnFocusRef: {current: null},
  title: 'Select',
  description: 'Select description',
  providers: [],
  warnIfUnsupportedProvider: false,
  itemConfig: fruitItemConfig,
}

describe('DynamicPickerDialog', () => {
  it('correctly renders empty dialog', async () => {
    setupExpectedAsyncErrorHandler()
    render(<DynamicPickerDialog {...defaultProps} />)

    expect(screen.getByText('No filter added. Add a filter using the input to match fruits.')).toBeInTheDocument()

    expectMockFetchCalledTimes('/fruities/picker/search?q=', 0)
  })

  it('correctly renders dialog with data', async () => {
    render(<DynamicPickerDialog {...defaultProps} query="any" />)

    await act(() =>
      mockFetch.resolvePendingRequest('/fruities/picker/search?q=any', {
        items: sampleFruits,
        totalCount: sampleFruits.length,
      }),
    )
    expectMockFetchCalledTimes('/fruities/picker/search?q=any', 1)

    expect(screen.getByText('Apricot')).toBeInTheDocument()
    expect(screen.getAllByText('9 fruits matching')).toHaveLength(2)
  })

  it('renders custom footer details', async () => {
    setupExpectedAsyncErrorHandler()
    const onRenderFooterDetails = () => <div data-testid="custom-footer">Custom Footer</div>
    render(<DynamicPickerDialog {...defaultProps} onRenderFooterDetails={onRenderFooterDetails} query="any" />)

    expect(screen.getByTestId('custom-footer')).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Apply'})).toBeInTheDocument()
  })
})

describe('getFiltersInvalidMessage', () => {
  it('returns sorted messages', () => {
    const result = getFiltersInvalidMessage([
      {type: 'text', value: 'test'},
      {type: 'filter', key: 'team', values: ['sales'], raw: 'team:sales', isNegated: false},
      {type: 'filter', key: 'env', values: ['prod'], raw: 'env:prod', isNegated: false},
      {type: 'filter', key: 'region', values: ['us'], raw: 'region:us', isNegated: true},
    ])

    expect(result).toHaveLength(4)
    expect(result[0]).toBe('Free text is not supported.')
    expect(result[1]).toBe('<pre>env</pre> is not supported.')
    expect(result[2]).toBe('<pre>region</pre> is not supported.')
    expect(result[3]).toBe('<pre>team</pre> is not supported.')
  })
})

const announcementArgs = {
  executedQuery: 'something',
  matchingItemsCount: 33,
  visibleItemsCount: 33,
  blankMessage: '',
  itemLiterals: {
    itemName: 'repository',
    itemsName: 'repositories',
    listTitle: 'Repositories list',
  },
}

describe('getResultsAnnouncement', () => {
  it('returns a message about empty input above other conditions', () => {
    const message = getDynamicResultsAnnouncement({
      ...announcementArgs,
      executedQuery: '',
    })

    expect(message).toBe('No filter added. Add a filter using the input to match repositories.')
  })

  it('returns a blank message if given (and query present)', () => {
    const message = getDynamicResultsAnnouncement({
      ...announcementArgs,
      blankMessage: 'Show this',
    })

    expect(message).toBe('Show this')
  })

  it('returns a message with the result counts if query present', () => {
    const message = getDynamicResultsAnnouncement(announcementArgs)

    expect(message).toBe('33 repositories matching')
  })

  it('returns a message with partial result counts if query present', () => {
    const message = getDynamicResultsAnnouncement({
      ...announcementArgs,
      matchingItemsCount: 3300,
      visibleItemsCount: 100,
    })

    expect(message).toBe('3300 repositories matching, showing first 100')
  })
})
