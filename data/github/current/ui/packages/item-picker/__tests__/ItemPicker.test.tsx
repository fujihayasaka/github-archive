import {useState} from 'react'
import {ItemPicker} from '../components/ItemPicker'
import {noop} from '@github-ui/noop'
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'

const defaultItems = ['item1', 'item2', 'item3']

const TestItemPicker = () => {
  const [selectedItems, setSelectedItems] = useState<string[]>([])
  const [isPickerOpen, setIsPickerOpen] = useState(false)

  const handleSelectionChange = (items: string[]) => {
    setSelectedItems(items)
  }

  const handlePickerClose = () => {
    setIsPickerOpen(false)
  }

  return (
    <ItemPicker
      items={defaultItems}
      initialSelectedItems={selectedItems}
      placeholderText="Select item"
      selectionVariant="multiple"
      loading={false}
      groups={[]}
      renderAnchor={anchorProps => <button {...anchorProps}>Open Item Picker</button>}
      getItemKey={item => item}
      convertToItemProps={item => {
        return {
          id: item,
          text: item,
          source: item,
        }
      }}
      onSelectionChange={handleSelectionChange}
      onClose={handlePickerClose}
      triggerOpen={isPickerOpen}
      filterItems={noop}
    />
  )
}

test('renders the items correctly after opening the picker', async () => {
  const {user} = render(<TestItemPicker />)

  const openButton = screen.getByRole('button', {name: 'Open Item Picker'})
  await user.click(openButton)

  const options = screen.getAllByRole('option')
  expect(options).toHaveLength(3)

  expect(options[0]).toHaveTextContent('item1')
  expect(options[1]).toHaveTextContent('item2')
  expect(options[2]).toHaveTextContent('item3')
})

test('pressing space while on a selected should toggle the selection', async () => {
  const {user} = render(<TestItemPicker />)

  const openButton = screen.getByRole('button', {name: 'Open Item Picker'})
  await user.click(openButton)

  const options = screen.getAllByRole('option')
  expect(options).toHaveLength(3)

  await user.keyboard('[arrowdown]')

  // We use the 2nd option, since a key down press will go to the 2nd option given the first one is already indirectly
  // activated. This is the primer behaviour.
  expect(options[1]).toHaveAttribute('data-is-active-descendant', 'activated-directly')

  await user.keyboard('[Space]')
  expect(options[1]).toHaveAttribute('aria-selected', 'true')

  // Press space again to deselect the first option
  await user.keyboard('[Space]')

  // Assert selection status
  expect(options[1]).toHaveAttribute('aria-selected', 'false')
})

test('improvedNoMatchAccessibility prevents no-matches from being selectable', async () => {
  const TestItemPickerWithNoItems = () => {
    const [selectedItems, setSelectedItems] = useState<string[]>([])
    const [isPickerOpen, setIsPickerOpen] = useState(false)

    return (
      <ItemPicker
        items={[]} // Empty items to test no-matches scenario
        initialSelectedItems={selectedItems}
        placeholderText="Select item"
        selectionVariant="multiple"
        loading={false}
        groups={[]}
        renderAnchor={anchorProps => <button {...anchorProps}>Open Item Picker</button>}
        getItemKey={item => item}
        convertToItemProps={item => ({
          id: item,
          text: item,
          source: item,
        })}
        onSelectionChange={setSelectedItems}
        onClose={() => setIsPickerOpen(false)}
        triggerOpen={isPickerOpen}
        filterItems={noop}
        improvedNoMatchAccessibility
      />
    )
  }

  const {user} = render(<TestItemPickerWithNoItems />)

  const openButton = screen.getByRole('button', {name: 'Open Item Picker'})
  await user.click(openButton)

  // With improvedNoMatchAccessibility enabled, there should be no selectable options
  const options = screen.queryAllByRole('option')
  expect(options).toHaveLength(0)

  // Verify that keyboard navigation doesn't find any focusable items
  await user.keyboard('[arrowdown]')
  await user.keyboard('[arrowup]')

  // Should still have no options after keyboard navigation
  expect(screen.queryAllByRole('option')).toHaveLength(0)
})

test('backward compatibility: shows no-results item when improvedNoMatchAccessibility is not enabled', async () => {
  const TestItemPickerWithNoItems = () => {
    const [selectedItems, setSelectedItems] = useState<string[]>([])
    const [isPickerOpen, setIsPickerOpen] = useState(true) // Start open to avoid timing issues

    return (
      <ItemPicker
        items={[]} // Empty items to test no-results scenario
        initialSelectedItems={selectedItems}
        placeholderText="Select item"
        selectionVariant="multiple"
        loading={false}
        groups={[]}
        renderAnchor={anchorProps => <button {...anchorProps}>Open Item Picker</button>}
        getItemKey={item => item}
        convertToItemProps={item => ({
          id: item,
          text: item,
          source: item,
        })}
        onSelectionChange={setSelectedItems}
        onClose={() => setIsPickerOpen(false)}
        triggerOpen={isPickerOpen}
        filterItems={noop}
        // Note: improvedNoMatchAccessibility is NOT provided (defaults to false)
      />
    )
  }

  render(<TestItemPickerWithNoItems />)

  // Wait for the picker to be rendered (since triggerOpen=true)
  await screen.findByRole('combobox')

  // Without improvedNoMatchAccessibility, there should be one option (the no-results item)
  const options = await screen.findAllByRole('option')
  expect(options).toHaveLength(1)

  // Verify the no-results item has the expected properties
  const noResultsOption = options[0]
  expect(noResultsOption).toBeDefined()
  expect(noResultsOption).toHaveTextContent('No results') // This is the correct text for empty items with no filter

  // Check if it's disabled - be flexible about implementation
  const isDisabled =
    noResultsOption!.hasAttribute('aria-disabled') ||
    noResultsOption!.hasAttribute('disabled') ||
    noResultsOption!.getAttribute('aria-disabled') === 'true'

  expect(isDisabled).toBe(true)
})
