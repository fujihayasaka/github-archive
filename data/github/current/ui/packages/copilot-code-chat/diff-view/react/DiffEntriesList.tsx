import type {FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {ActionList} from '@primer/react'
import {useMemo, type ReactElement} from 'react'
import {mapWith, mapWithout} from '../../map-utils'
import type {DiffEntryData} from '../shared/use-get-diff-entry-data'

interface EntryItemProps {
  entry: DiffEntryData
  selected: boolean
  onSelect: (reference: FileDiffReference) => void
  onDeselect: () => void
}

const EntryItem: React.FC<EntryItemProps> = ({entry, selected, onSelect, onDeselect}) => {
  return entry.reference ? (
    <ActionList.Item
      disabled={!entry.reference}
      selected={selected}
      onSelect={() => (selected ? onDeselect() : onSelect(entry.reference as FileDiffReference))}
    >
      {entry.path}
    </ActionList.Item>
  ) : (
    <ActionList.Item disabled={!entry.reference} inactiveText="Copilot is not available for this file">
      {entry.path}
    </ActionList.Item>
  )
}

interface DiffEntriesListProps {
  emptyState: ReactElement
  filter: string
  diffEntries: DiffEntryData[]
  onSelectedReferencesChange: (newSelectedReferences: Map<string, FileDiffReference>) => void
  selectedReferences: ReadonlyMap<string, FileDiffReference>
}

export const DiffEntriesList: React.FC<DiffEntriesListProps> = ({
  diffEntries,
  emptyState,
  filter,
  onSelectedReferencesChange,
  selectedReferences,
}) => {
  const filteredEntries = useMemo(() => {
    const lowercaseFilter = filter.toLowerCase()
    const newFilteredEntries = []
    for (const entry of diffEntries ?? [])
      if (entry.path.toLowerCase().includes(lowercaseFilter)) newFilteredEntries.push(entry)
    return newFilteredEntries
  }, [diffEntries, filter])

  const onSelectEntry = (path: string, reference: FileDiffReference) =>
    onSelectedReferencesChange(mapWith(selectedReferences, [path, reference]))

  const onDeselectEntry = (path: string) => onSelectedReferencesChange(mapWithout(selectedReferences, path))

  if (filteredEntries.length === 0) return emptyState

  return (
    <ActionList>
      {filteredEntries.map(entry => (
        <EntryItem
          key={entry.path}
          entry={entry}
          selected={selectedReferences.has(entry.path)}
          onSelect={reference => onSelectEntry(entry.path, reference)}
          onDeselect={() => onDeselectEntry(entry.path)}
        />
      ))}
    </ActionList>
  )
}
