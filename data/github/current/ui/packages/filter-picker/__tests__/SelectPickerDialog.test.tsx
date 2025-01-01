// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {render} from '@github-ui/react-core/test-utils'
import {act, screen} from '@testing-library/react'

import {SelectPickerDialog} from '../SelectPickerDialog'
import {fruitItemConfig, sampleFruits} from '../test-utils/mock-data'

const defaultProps = {
  selected: [],
  onSubmit: jest.fn(),
  onDismiss: jest.fn(),
  returnFocusRef: {current: null},
  title: 'Select',
  description: 'Select description',
  providers: [],
  itemConfig: fruitItemConfig,
}

describe('SelectPickerDialog', () => {
  it('correctly renders loading dialog', async () => {
    render(<SelectPickerDialog {...defaultProps} selectionVariant="multiple" />)

    expect(screen.getAllByText('Loading fruits...')).toHaveLength(2)

    expectMockFetchCalledTimes('/fruities/picker/search?q=', 1)
    await waitForItems([])

    expect(screen.getAllByText('No fruits to show.')).toHaveLength(2)
  })

  it('correctly renders multi-select dialog with data', async () => {
    render(<SelectPickerDialog {...defaultProps} selectionVariant="multiple" />)
    await waitForItems()

    expect(screen.getByText('Apricot')).toBeInTheDocument()
  })

  it('correctly renders single-select dialog with data', async () => {
    render(<SelectPickerDialog {...defaultProps} selectionVariant="single" />)
    await waitForItems()

    expect(screen.getByText('Apricot')).toBeInTheDocument()
  })

  it('calls onChange when selecting and deselecting items', async () => {
    const onChangeMock = jest.fn()
    const {user} = render(<SelectPickerDialog {...defaultProps} onChange={onChangeMock} selectionVariant="multiple" />)
    await waitForItems()

    const apricot = screen.getByText('Apricot')
    await user.click(apricot)
    expect(onChangeMock).toHaveBeenCalledWith([expect.objectContaining({name: 'Apricot'})])

    await user.click(apricot)
    expect(onChangeMock).toHaveBeenCalledWith([])
  })

  it('submits on cmd + Enter', async () => {
    const onSubmitMock = jest.fn()
    const {user} = render(<SelectPickerDialog {...defaultProps} onSubmit={onSubmitMock} selectionVariant="multiple" />)

    const searchBar = screen.getByRole('combobox')
    await user.click(searchBar)

    await user.keyboard('{Control>}{Enter}')

    expect(onSubmitMock).toHaveBeenCalled()
  })

  it('renders custom footer', async () => {
    render(
      <SelectPickerDialog
        {...defaultProps}
        onRenderFooterDetails={() => <div data-testid="custom-footer" />}
        selectionVariant="multiple"
      />,
    )
    await waitForItems()

    expect(screen.getByTestId('custom-footer')).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Select'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
  })
})

async function waitForItems(items = sampleFruits) {
  await act(() =>
    mockFetch.resolvePendingRequest('/fruities/picker/search?q=', {
      items,
      totalCount: items.length,
    }),
  )
}
