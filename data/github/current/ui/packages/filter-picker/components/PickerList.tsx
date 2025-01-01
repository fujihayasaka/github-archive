import {ActionList, type ActionListProps} from '@primer/react'

import type {IPickerItem} from '../types'

interface PickerListProps<T extends IPickerItem> {
  selectionVariant: ActionListProps['selectionVariant']
  items: T[]
  selectedItems: T[]
  onRenderItemName(item: T): React.ReactNode
  onRenderItemLeadingVisual?(item: T): React.ReactNode
  setSelectedItems(items: T[]): void
  title: string
}

export function PickerList<T extends IPickerItem>({
  selectionVariant,
  items,
  selectedItems,
  setSelectedItems,
  onRenderItemLeadingVisual,
  onRenderItemName,
  title,
}: PickerListProps<T>) {
  const selectedIds = new Set(selectedItems.map(item => item.id))

  const onSelectItem = (item: T) => {
    const isSelected = selectedIds.has(item.id)

    if (isSelected) {
      setSelectedItems(selectedItems.filter(prev => prev.id !== item.id))
    } else {
      setSelectedItems(selectionVariant === 'single' ? [item] : [...selectedItems, item])
    }
  }

  return (
    <ActionList selectionVariant={selectionVariant} role="listbox" aria-label={title}>
      {items.map(item => (
        <ActionList.Item
          key={item.id}
          role="option"
          selected={selectedIds.has(item.id)}
          onSelect={() => onSelectItem(item)}
        >
          {onRenderItemLeadingVisual && (
            <ActionList.LeadingVisual>{onRenderItemLeadingVisual(item)}</ActionList.LeadingVisual>
          )}
          {onRenderItemName(item)}
        </ActionList.Item>
      ))}
    </ActionList>
  )
}
