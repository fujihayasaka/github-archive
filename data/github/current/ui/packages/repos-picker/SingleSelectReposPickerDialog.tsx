import {useState} from 'react'

import {HiddenSelectionBanner} from './components/HiddenSelectionBanner'
import {getBlankMessage, ListMessage} from './components/ListMessage'
import {PartialResultsRow} from './components/PartialResultsRow'
import {PickerDialog} from './components/PickerDialog'
import {PickerList} from './components/PickerList'
import {ReposPickerHeaderContent} from './components/ReposPickerHeaderContent'
import {concatAndDedup} from './helper/concat-and-dedup'
import {useQueryRepositories} from './hooks/use-query-repositories'
import type {CommonDialogProps, SingleSelectProps} from './types'

type SingleSelectReposPickerDialogProps = SingleSelectProps & CommonDialogProps

export function SingleSelectReposPickerDialog({
  orgLogin,
  selected,
  onSubmit,
  onDismiss,
  returnFocusRef,
}: SingleSelectReposPickerDialogProps) {
  const [query, setQuery] = useState('')

  const [selectedItem, setSelectedItem] = useState(selected)
  const [snapshotSelectedItem, setSnapshotSelectedItem] = useState(selectedItem)

  const results = useQueryRepositories({orgLogin, query})

  const onApply = () => {
    onSubmit(selectedItem)
    onDismiss()
  }

  const fetchedItems = results.data?.repositories || []
  const visibleItems = concatAndDedup(snapshotSelectedItem ? [snapshotSelectedItem] : [], fetchedItems)
  const blankMessage = getBlankMessage(results, visibleItems)
  const visibleIds = new Set(visibleItems.map(item => item.id))
  const isHiddenSelectedItem = selectedItem && !visibleIds.has(selectedItem.id)

  const onQueryChanged = (newQuery: string) => {
    setQuery(newQuery)
    setSnapshotSelectedItem(newQuery ? undefined : selectedItem)
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
        },
      ]}
      returnFocusRef={returnFocusRef}
      renderHeader={({initialFocusRef}) => (
        <div>
          <ReposPickerHeaderContent
            dialogTitle="Select a repository"
            inputRef={initialFocusRef}
            orgLogin={orgLogin}
            onDismiss={onDismiss}
            setQuery={onQueryChanged}
          />
        </div>
      )}
      renderBody={() => (
        <PickerDialog.Body>
          <HiddenSelectionBanner hiddenSelectedCount={isHiddenSelectedItem ? 1 : 0} />
          {blankMessage ? (
            <ListMessage>{blankMessage}</ListMessage>
          ) : (
            <PickerList
              mode="single"
              items={visibleItems}
              selectedItems={selectedItem ? [selectedItem] : []}
              setSelectedItems={items => setSelectedItem(items[0])}
            />
          )}
          <PartialResultsRow itemCount={visibleItems.length} totalCount={results.data?.repositoryCount || 0} />
        </PickerDialog.Body>
      )}
    />
  )
}
