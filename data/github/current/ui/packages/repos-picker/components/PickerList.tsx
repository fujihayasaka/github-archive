import {ActionList} from '@primer/react'

import type {PickerRepository} from '../types'
import {ListItemRepoIcon} from './ListItemRepoIcon'

interface PickerListProps {
  mode: 'single' | 'multiple'
  items: PickerRepository[]
  selectedItems: PickerRepository[]
  setSelectedItems: (repositories: PickerRepository[]) => void
}

export function PickerList({mode, items, selectedItems, setSelectedItems}: PickerListProps) {
  const selectedIds = new Set(selectedItems.map(repo => repo.id))

  const onSelectItem = (repo: PickerRepository) => {
    const isSelected = selectedIds.has(repo.id)

    if (isSelected) {
      setSelectedItems(selectedItems.filter(item => item.id !== repo.id))
    } else {
      setSelectedItems(mode === 'single' ? [repo] : [...selectedItems, repo])
    }
  }

  return (
    <ActionList selectionVariant={mode} role="listbox" aria-label="Repository List">
      {items.map(repo => (
        <ActionList.Item
          key={repo.id}
          role="option"
          selected={selectedIds.has(repo.id)}
          onSelect={() => onSelectItem(repo)}
        >
          <ActionList.LeadingVisual>
            <ListItemRepoIcon visibility={repo.visibility} />
          </ActionList.LeadingVisual>
          {repo.name}
        </ActionList.Item>
      ))}
    </ActionList>
  )
}
