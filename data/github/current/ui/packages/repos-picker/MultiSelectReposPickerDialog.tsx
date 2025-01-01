import {useState} from 'react'

import {HiddenSelectionBanner} from './components/HiddenSelectionBanner'
import {getBlankMessage, ListMessage} from './components/ListMessage'
import {PartialResultsRow} from './components/PartialResultsRow'
import {PickerDialog} from './components/PickerDialog'
import {PickerList} from './components/PickerList'
import {ReposPickerHeaderContent} from './components/ReposPickerHeaderContent'
import {SelectAllRow} from './components/SelectAllRow'
import {concatAndDedup, PAGE_SIZE} from './helper/concat-and-dedup'
import {useQueryRepositories} from './hooks/use-query-repositories'
import type {CommonDialogProps, MultiSelectProps, PickerRepository} from './types'

type MultiSelectReposPickerDialogProps = MultiSelectProps & CommonDialogProps

export function MultiSelectReposPickerDialog({
  orgLogin,
  selected,
  onSubmit,
  onDismiss,
  returnFocusRef,
}: MultiSelectReposPickerDialogProps) {
  const [query, setQuery] = useState('')

  const [selectedItems, setSelectedItems] = useState(selected || [])
  const [snapshotSelectedItems, setSnapshotSelectedItems] = useState(selectedItems)
  const skipFirstPageResults = !query && snapshotSelectedItems.length > PAGE_SIZE

  const results = useQueryRepositories({orgLogin, query, enabled: !skipFirstPageResults})

  const onApply = () => {
    onSubmit(selectedItems)
    onDismiss()
  }

  const fetchedItems = results.data?.repositories || []
  const visibleItems = concatAndDedup(snapshotSelectedItems, fetchedItems)
  const blankMessage = getBlankMessage(results, visibleItems)
  const visibleIds = new Set(visibleItems.map(item => item.id))
  const [visibleSelectedItems, hiddenSelectedItems] = partitionArray(selectedItems, item => visibleIds.has(item.id))

  const onQueryChanged = (newQuery: string) => {
    setQuery(newQuery)
    setSnapshotSelectedItems(newQuery ? [] : selectedItems)
  }

  return (
    <PickerDialog
      onClose={onDismiss}
      footerButtons={[
        {
          onClick: onDismiss,
          content: 'Cancel',
        },
        {
          buttonType: 'primary',
          onClick: onApply,
          content: 'Select',
          count: selectedItems.length > 0 ? selectedItems.length : undefined,
        },
      ]}
      returnFocusRef={returnFocusRef}
      renderHeader={({initialFocusRef}) => (
        <div>
          <ReposPickerHeaderContent
            dialogTitle="Select repositories"
            inputRef={initialFocusRef}
            orgLogin={orgLogin}
            onDismiss={onDismiss}
            setQuery={onQueryChanged}
          />
          <SelectAllRow
            itemsCount={visibleItems.length}
            selectedCount={visibleSelectedItems.length}
            onSelectAll={() => setSelectedItems(hiddenSelectedItems.concat(visibleItems))}
            onSelectNone={() => setSelectedItems(hiddenSelectedItems)}
          />
        </div>
      )}
      renderBody={() => (
        <PickerDialog.Body>
          <HiddenSelectionBanner hiddenSelectedCount={hiddenSelectedItems.length} />
          {blankMessage ? (
            <ListMessage>{blankMessage}</ListMessage>
          ) : (
            <PickerList
              mode="multiple"
              items={visibleItems}
              selectedItems={selectedItems}
              setSelectedItems={setSelectedItems}
            />
          )}
          <PartialResultsRow itemCount={visibleItems.length} totalCount={results.data?.repositoryCount || 0} />
        </PickerDialog.Body>
      )}
    />
  )
}

function partitionArray(array: PickerRepository[], predicate: (item: PickerRepository) => boolean) {
  return array.reduce<[PickerRepository[], PickerRepository[]]>(
    (pairOfArrays, item) => {
      const targetArray = predicate(item) ? pairOfArrays[0] : pairOfArrays[1]
      targetArray.push(item)
      return pairOfArrays
    },
    [[], []],
  )
}
