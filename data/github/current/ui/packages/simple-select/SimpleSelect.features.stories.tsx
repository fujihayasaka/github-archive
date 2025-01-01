import type {Meta} from '@storybook/react'
import React from 'react'
import {type Items, SimpleSelect} from './SimpleSelect'

const meta = {
  title: 'Recipes/SimpleSelect/Features',
  component: SimpleSelect,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    selectionVariant: {
      control: {
        type: 'select',
        options: ['single', 'multiple'],
      },
    },
    items: {
      control: {
        type: 'object',
      },
    },
    label: {
      control: {
        type: 'text',
      },
    },
  },
} satisfies Meta<typeof SimpleSelect>

export default meta

export const SelectSingle = () => {
  const items = [
    {label: 'Item 1', id: 'item-1', selected: true, groupId: 0},
    {label: 'Item 2', id: 'item-2', selected: false},
    {label: 'Item 3', id: 'item-3', selected: false},
  ]

  const [itemState, setItemState] = React.useState(items)
  const handleSelect = (selectedItem: {id: string}) => {
    const updatedItems = itemState.map(item =>
      item.id === selectedItem.id ? {...item, selected: true} : {...item, selected: false},
    )
    setItemState(updatedItems)
  }

  return <SimpleSelect items={itemState} selectionVariant="single" label="Select an item" onSelect={handleSelect} />
}

export const SelectMultiple = () => {
  const items = [
    {label: 'Item 1', id: 'item-1', selected: true},
    {label: 'Item 2', id: 'item-2', selected: false},
    {label: 'Item 3', id: 'item-3', selected: false},
  ]

  const [itemState, setItemState] = React.useState(items)
  const handleSelect = (selectedItem: {id: string}) => {
    const updatedItems = itemState.map(item =>
      item.id === selectedItem.id ? {...item, selected: !item.selected} : item,
    )
    setItemState(updatedItems)
  }

  const handleSave = (savedItems: Items[]) => {
    setItemState(savedItems)
  }

  const handleCancel = (prevItems: Items[]) => {
    setItemState(prevItems)
  }

  return (
    <SimpleSelect
      items={itemState}
      selectionVariant="multiple"
      label="Select an item"
      onSelect={handleSelect}
      onSave={handleSave}
      onCancel={handleCancel}
      focusTarget="first-item"
    />
  )
}

export const SelectMultipleNoFooter = () => {
  const items = [
    {label: 'Item 1', id: 'item-1', selected: true},
    {label: 'Item 2', id: 'item-2', selected: true},
    {label: 'Item 3', id: 'item-3', selected: false},
  ]

  const [itemState, setItemState] = React.useState(items)
  const handleSelect = (selectedItem: {id: string}) => {
    const updatedItems = itemState.map(item =>
      item.id === selectedItem.id ? {...item, selected: !item.selected} : item,
    )
    setItemState(updatedItems)
  }

  return <SimpleSelect items={itemState} selectionVariant="multiple" label="Select an item" onSelect={handleSelect} />
}

export const SelectWithCustomRenderText = () => {
  const items = [
    {label: 'Item 1', id: 'item-1', selected: false},
    {label: 'Item 2', id: 'item-2', selected: false},
    {label: 'Item 3', id: 'item-3', selected: false},
  ]

  const [itemState, setItemState] = React.useState(items)
  const handleSelect = (selectedItem: {id: string}) => {
    const updatedItems = itemState.map(item =>
      item.id === selectedItem.id ? {...item, selected: true} : {...item, selected: false},
    )
    setItemState(updatedItems)
  }
  const renderText = () => {
    const selectedItems = itemState.filter(item => item.selected)

    return (
      <div className="text-muted">
        <span className="fgColor-muted">Select: </span>
        {selectedItems.length > 0 ? selectedItems.map(item => item.label).join(', ') : 'No items selected'}
      </div>
    )
  }

  const handleSave = (savedItems: Items[]) => {
    setItemState(savedItems)
  }

  const handleCancel = (prevItems: Items[]) => {
    setItemState(prevItems)
  }

  return (
    <SimpleSelect
      items={itemState}
      selectionVariant="single"
      onSelect={handleSelect}
      renderText={renderText}
      onSave={handleSave}
      onCancel={handleCancel}
    />
  )
}

export const SelectMultipleWithGroups = () => {
  const items = [
    {label: 'Item 1', id: 'item-1', selected: true, groupId: 1},
    {label: 'Item 2', id: 'item-2', selected: false},
    {label: 'Item 3', id: 'item-3', selected: true},
    {label: 'Item 4', id: 'item-4', selected: false, groupId: 1},
    {label: 'Item 5', id: 'item-5', selected: false, groupId: 1},
    {label: 'Item 6', id: 'item-6', selected: false, groupId: 1},
    {label: 'Item 7', id: 'item-7', selected: false, groupId: 2},
    {label: 'Item 8', id: 'item-8', selected: false, groupId: 2},
    {label: 'Item 9', id: 'item-9', selected: true, groupId: 3},
    {label: 'Item 10', id: 'item-10', selected: false, groupId: 3},
  ]

  const [itemState, setItemState] = React.useState(items)
  const handleSelect = (selectedItem: {id: string}) => {
    const updatedItems = itemState.map(item =>
      item.id === selectedItem.id ? {...item, selected: !item.selected} : item,
    )
    setItemState(updatedItems)
  }

  return (
    <SimpleSelect
      items={itemState}
      selectionVariant="multiple"
      label="Select an item"
      onSelect={handleSelect}
      onSave={savedItems => {
        setItemState(savedItems)
      }}
      onCancel={prevItems => {
        setItemState(prevItems)
      }}
    />
  )
}

export const ControlledSelect = () => {
  const [selectedItems, setSelectedItems] = React.useState<Items[]>([])
  const items = [
    {label: 'Item 1', id: 'item-1', selected: false},
    {label: 'Item 2', id: 'item-2', selected: false},
    {label: 'Item 3', id: 'item-3', selected: false},
  ]

  const selection = (selected: Items[]) => {
    setSelectedItems(selected)
  }

  return (
    <>
      <p>Selected Item: {selectedItems[0]?.label}</p>
      <SimpleSelect items={items} selectionVariant="single" label="Select an item" selectable={selection} />
    </>
  )
}

export const ControlledMultiSelect = () => {
  const [selectedItems, setSelectedItems] = React.useState<Items[]>([])
  const items = [
    {label: 'Item 1', id: 'item-1', selected: false},
    {label: 'Item 2', id: 'item-2', selected: false},
    {label: 'Item 3', id: 'item-3', selected: false},
  ]

  const selection = (selected: Items[]) => setSelectedItems(selected)

  return (
    <>
      <p>Selected Items: {selectedItems.length}</p>
      <SimpleSelect items={items} selectionVariant="multiple" label="Select an item" selectable={selection} />
    </>
  )
}
