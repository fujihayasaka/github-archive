import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {type Items, SimpleSelect} from '../SimpleSelect'
import React from 'react'

const items = [
  {label: 'Item 1', id: 'item-1', selected: true},
  {label: 'Item 2', id: 'item-2', selected: false},
  {label: 'Item 3', id: 'item-3', selected: false},
]

const UncontrolledSimpleSelect = ({selectionVariant = 'single'}: {selectionVariant: 'single' | 'multiple'}) => {
  const [uncontrolledItems, setUncontrolledItems] = React.useState(items)

  const onSelect = (selectedItem: {id: string}) => {
    const updatedItems = uncontrolledItems.map(item =>
      item.id === selectedItem.id
        ? {...item, selected: !item.selected}
        : selectionVariant === 'multiple'
          ? item
          : {...item, selected: false},
    )
    setUncontrolledItems(updatedItems)
  }

  return (
    <SimpleSelect
      items={uncontrolledItems}
      selectionVariant={selectionVariant}
      label="Select an item"
      onSelect={onSelect}
    />
  )
}

const UncontrolledSimpleSelectWithSave = () => {
  const [uncontrolledItems, setUncontrolledItems] = React.useState(items)

  const onSelect = (selectedItem: {id: string}) => {
    const updatedItems = uncontrolledItems.map(item =>
      item.id === selectedItem.id ? {...item, selected: !item.selected} : item,
    )
    setUncontrolledItems(updatedItems)
  }

  const onSave = (savedItems: Items[]) => {
    setUncontrolledItems(savedItems)
  }

  const onCancel = (prevItems: Items[]) => {
    setUncontrolledItems(prevItems)
  }

  return (
    <SimpleSelect
      items={uncontrolledItems}
      selectionVariant="single"
      label="Select an item"
      onSelect={onSelect}
      onSave={onSave}
      onCancel={onCancel}
    />
  )
}

const UncontrolledSimpleSelectWithoutSave = () => {
  const [uncontrolledItems, setUncontrolledItems] = React.useState(items)

  const onSelect = (selectedItem: {id: string}) => {
    const updatedItems = uncontrolledItems.map(item =>
      item.id === selectedItem.id ? {...item, selected: !item.selected} : item,
    )
    setUncontrolledItems(updatedItems)
  }

  return <SimpleSelect items={uncontrolledItems} selectionVariant="single" label="Select an item" onSelect={onSelect} />
}

describe('SimpleSelect', () => {
  it('Renders the Select', () => {
    render(<SimpleSelect items={items} selectionVariant="single" label="Select an item" onSelect={() => {}} />)
    expect(screen.getByRole('button')).toHaveTextContent('Select an item')
  })

  it('Handles single selection', async () => {
    const handleSelect = jest.fn()
    const {user} = render(
      <SimpleSelect items={items} selectionVariant="single" label="Select an item" onSelect={handleSelect} />,
    )
    await user.click(screen.getByRole('button'))
    await user.click(screen.getByText('Item 1'))
    expect(handleSelect).toHaveBeenCalledWith(items[0])
  })

  it('Handles multiple selection', async () => {
    const {user} = render(<UncontrolledSimpleSelect selectionVariant={'multiple'} />)

    await user.click(screen.getByRole('button'))
    await user.click(screen.getByText('Item 1'))
    await user.click(screen.getByText('Item 2'))
    await user.click(screen.getByText('Item 3'))

    expect(screen.getAllByRole('option', {selected: true})).toHaveLength(2)
  })

  it('Closes when selected', async () => {
    const {user} = render(<UncontrolledSimpleSelect selectionVariant={'single'} />)

    await user.click(screen.getByRole('button'))
    await user.click(screen.getByText('Item 1'))
    expect(screen.queryByRole('listbox')).not.toBeInTheDocument()

    await user.click(screen.getByRole('button'))
    await user.click(screen.getByText('Item 2'))
    expect(screen.queryByRole('listbox')).not.toBeInTheDocument()

    await user.click(screen.getByRole('button'))
    await user.click(screen.getByText('Item 3'))
    expect(screen.queryByRole('listbox')).not.toBeInTheDocument()

    await user.click(screen.getByRole('button'))

    expect(screen.getAllByRole('option', {selected: true})).toHaveLength(1)
    expect(screen.getByRole('option', {selected: true})).toHaveAccessibleName('Item 3')
  })

  it('Handles controlled single selection', async () => {
    const handleSelect = jest.fn()
    const {user} = render(
      <SimpleSelect items={items} selectionVariant="single" label="Select an item" selectable={handleSelect} />,
    )
    await user.click(screen.getByRole('button'))
    await user.click(screen.getByText('Item 2'))
    expect(handleSelect).toHaveBeenCalledWith([items[1]])
  })

  it('Handles controlled multiple selection', async () => {
    const handleSelect = jest.fn()
    const {user} = render(
      <SimpleSelect items={items} selectionVariant="multiple" label="Select an item" selectable={handleSelect} />,
    )
    await user.click(screen.getByRole('button'))
    await user.click(screen.getByText('Item 2'))

    expect(handleSelect).toHaveBeenCalled()

    await user.click(screen.getByText('Item 3'))
    expect(handleSelect).toHaveBeenCalledWith(items)

    expect(screen.getAllByRole('option', {selected: true})).toHaveLength(3)
  })

  it('Handles cancel button click', async () => {
    const handleCancel = jest.fn()
    const {user} = render(
      <SimpleSelect
        items={items}
        selectionVariant="single"
        label="Select an item"
        onCancel={handleCancel}
        onSave={() => {}}
      />,
    )
    await user.click(screen.getByRole('button'))
    await user.click(screen.getByText('Item 1'))
    await user.click(screen.getByText('Cancel'))

    expect(handleCancel).toHaveBeenCalled()
  })

  it('Does not save if cancel button is clicked', async () => {
    const {user} = render(<UncontrolledSimpleSelectWithSave />)

    await user.click(screen.getByRole('button'))
    await user.click(screen.getByText('Item 1'))
    await user.click(screen.getByText('Item 2'))
    await user.click(screen.getByText('Item 3'))

    await user.click(screen.getByText('Cancel'))
    await user.click(screen.getByRole('button'))

    expect(screen.getAllByRole('option', {selected: true})).toHaveLength(1)
  })

  it('Saves if save button is clicked', async () => {
    const {user} = render(<UncontrolledSimpleSelectWithSave />)

    await user.click(screen.getByRole('button'))
    await user.click(screen.getByText('Item 2'))
    await user.click(screen.getByText('Item 3'))

    await user.click(screen.getByText('Save'))
    await user.click(screen.getByRole('button'))

    expect(screen.getAllByRole('option', {selected: true})).toHaveLength(3)
  })

  it('Closes the select on single selection when an item is selected', async () => {
    const {user} = render(<UncontrolledSimpleSelectWithoutSave />)
    await user.click(screen.getByRole('button'))
    await user.click(screen.getByText('Item 1'))

    expect(screen.queryByRole('listbox')).not.toBeInTheDocument()
  })
})
