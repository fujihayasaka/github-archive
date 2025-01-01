import type {FileDiffReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {ActionList, Spinner} from '@primer/react'
import {useEffect, useMemo, useState, type ReactElement} from 'react'
import {mapWith, mapWithout} from '../../map-utils'

interface EntryItemProps {
  entry: DiffEntryData
  selected: boolean
  onSelect: (reference: FileDiffReference) => void
  onDeselect: () => void
}

function EntryItem({entry, selected, onSelect, onDeselect}: EntryItemProps) {
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
  onSelectedReferencesChange: (newSelectedReferences: Map<string, FileDiffReference>) => void
  selectedReferences: ReadonlyMap<string, FileDiffReference>
  pullRequestId: string
}

const ENTRIES_LIMIT = 100
const PAGE_SIZE = 25

export function DiffEntriesList({
  pullRequestId,
  filter,
  selectedReferences,
  onSelectedReferencesChange,
  emptyState,
}: DiffEntriesListProps) {
  const {entriesData, loadNext, hasNext, loading} = useGetDiffEntryData(pullRequestId)
  const totalLoaded = entriesData.length ?? 0

  // Load all pages up to the limit (making several small requests feels more responsive than the user having to wait
  // on one large one):
  useEffect(() => {
    if (hasNext && !loading && totalLoaded < ENTRIES_LIMIT) {
      // Ensure the last page is reduced so we don't go over the limit
      const thisPageSize = Math.min(ENTRIES_LIMIT - totalLoaded, PAGE_SIZE)
      loadNext(thisPageSize)
    }
  }, [totalLoaded, hasNext, loading, loadNext])

  const filteredEntries = useMemo(() => {
    const lowercaseFilter = filter.toLowerCase()
    const newFilteredEntries = []
    for (const entry of entriesData ?? [])
      if (entry.path.toLowerCase().includes(lowercaseFilter)) newFilteredEntries.push(entry)
    return newFilteredEntries
  }, [entriesData, filter])

  const onSelectEntry = (path: string, reference: FileDiffReference) =>
    onSelectedReferencesChange(mapWith(selectedReferences, [path, reference]))

  const onDeselectEntry = (path: string) => onSelectedReferencesChange(mapWithout(selectedReferences, path))

  return filteredEntries.length === 0 && !loading ? (
    emptyState
  ) : (
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
      <div className="px-3 py-2 d-flex gap-2">
        {loading && (
          <>
            <Spinner size="small" />
            <span>Loading more files…</span>
          </>
        )}
        {hasNext && !loading && totalLoaded === ENTRIES_LIMIT && `Maximum of ${ENTRIES_LIMIT} files loaded`}
      </div>
    </ActionList>
  )
}

interface DiffEntryData {
  path: string
  reference?: FileDiffReference
}

export function useGetDiffEntryData(pullRequestId: string) {
  const [loading, setLoading] = useState(true)

  const [entriesData, setEntriesData] = useState<DiffEntryData[]>([])

  useEffect(() => {
    setEntriesData([])

    setLoading(false)
  }, [])

  return {
    entriesData,
    loading,
    loadNext: (pageSize: number) => {
      if (pageSize > 0) {
        setLoading(true)
        setTimeout(() => setLoading(false), 1000)
      }
    },
    hasNext: false,
    pullRequestId,
  }
}
