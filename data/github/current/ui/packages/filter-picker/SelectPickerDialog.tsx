import {human} from '@github-ui/formatters'
import type {ActionListProps} from '@primer/react'
import {AriaStatus} from '@primer/react/experimental'
import {useState} from 'react'

import {HiddenSelectionBanner} from './components/HiddenSelectionBanner'
import {getBlankMessage, getResultsAnnouncement, ListMessage} from './components/ListMessage'
import {PartialResultsRow} from './components/PartialResultsRow'
import {PickerDialog} from './components/PickerDialog'
import {PickerHeaderContent} from './components/PickerHeaderContent'
import {PickerList} from './components/PickerList'
import {SelectAllRow} from './components/SelectAllRow'
import {concatAndDedup, PAGE_SIZE} from './helper/concat-and-dedup'
import {useQuerySearch} from './hooks/use-query-search'
import type {InnerDialogProps, IPickerItem, MultiSelectProps} from './types'

interface SelectPickerDialogProps<T extends IPickerItem> extends MultiSelectProps<T>, InnerDialogProps<T> {
  selectionVariant: ActionListProps['selectionVariant']
}

export function SelectPickerDialog<T extends IPickerItem>({
  selected,
  onChange,
  onSubmit,
  onDismiss,
  returnFocusRef,
  selectionVariant,
  title,
  description,
  providers,
  itemConfig: {getSearchUrl, onRenderItemName, onRenderItemLeadingVisual, ...itemLiterals},
  onRenderFooterDetails,
}: SelectPickerDialogProps<T>) {
  const [query, setQuery] = useState('')

  const [selectedItems, setSelectedItems] = useState(selected || [])
  const [snapshotSelectedItems, setSnapshotSelectedItems] = useState(selectedItems)
  const skipFirstPageResults = !query && snapshotSelectedItems.length > PAGE_SIZE

  const results = useQuerySearch<T>({searchUrl: getSearchUrl(query), enabled: !skipFirstPageResults})
  const onApply = () => {
    onSubmit(selectedItems)
    onDismiss()
  }

  const onCancel = () => {
    onChange?.(selected || [])
    onDismiss()
  }

  const select = (items: T[]) => {
    setSelectedItems(items)
    onChange?.(items)
  }

  const fetchedItems = results.data?.items || []
  const visibleItems = concatAndDedup(snapshotSelectedItems, fetchedItems)
  const blankMessage = getBlankMessage(results, visibleItems, itemLiterals)
  const visibleIds = new Set(visibleItems.map(item => item.id))
  const [visibleSelectedItems, hiddenSelectedItems] = partitionArray(selectedItems, item => visibleIds.has(item.id))

  const totalItemsCount = results.data?.totalCount || 0
  const resultsMessage = getResultsAnnouncement({
    blankMessage,
    itemsCount: visibleItems.length,
    totalItemsCount,
    itemLiterals,
  })

  const onQueryChanged = (newQuery: string) => {
    setQuery(newQuery)
    setSnapshotSelectedItems(newQuery ? [] : selectedItems)
  }

  return (
    <PickerDialog
      onClose={onCancel}
      footerButtons={[
        {
          onClick: onCancel,
          content: 'Cancel',
        },
        {
          buttonType: 'primary',
          onClick: onApply,
          content: 'Select',
          count: selectionVariant === 'multiple' && selectedItems.length > 0 ? human(selectedItems.length) : undefined,
        },
      ]}
      onSubmit={onApply}
      returnFocusRef={returnFocusRef}
      renderHeader={({dialogLabelId, dialogDescriptionId}) => (
        <div>
          <PickerHeaderContent
            dialogTitle={title}
            dialogLabelId={dialogLabelId}
            dialogDescription={description}
            dialogDescriptionId={dialogDescriptionId}
            inputLabel={`Filter ${itemLiterals.itemsName}`}
            onDismiss={onDismiss}
            onQueryExecuted={onQueryChanged}
            providers={providers}
          />
          {selectionVariant === 'multiple' && (
            <SelectAllRow
              itemsCount={visibleItems.length}
              selectedCount={visibleSelectedItems.length}
              onSelectAll={() => select(hiddenSelectedItems.concat(visibleItems))}
              onSelectNone={() => select(hiddenSelectedItems)}
            />
          )}
          <AriaStatus announceOnShow className="sr-only">
            {resultsMessage}
          </AriaStatus>
        </div>
      )}
      renderBody={() => (
        <PickerDialog.Body>
          <HiddenSelectionBanner hiddenSelectedCount={hiddenSelectedItems.length} />
          {blankMessage ? (
            <ListMessage>{blankMessage}</ListMessage>
          ) : (
            <PickerList
              items={visibleItems}
              selectionVariant={selectionVariant}
              selectedItems={selectedItems}
              setSelectedItems={select}
              onRenderItemLeadingVisual={onRenderItemLeadingVisual}
              onRenderItemName={onRenderItemName}
              title={itemLiterals.listTitle}
            />
          )}
          <PartialResultsRow itemCount={visibleItems.length} totalCount={totalItemsCount} />
        </PickerDialog.Body>
      )}
      onRenderFooterDetails={onRenderFooterDetails}
    />
  )
}

function partitionArray<T extends IPickerItem>(array: T[], predicate: (item: T) => boolean) {
  return array.reduce<[T[], T[]]>(
    (pairOfArrays, item) => {
      const targetArray = predicate(item) ? pairOfArrays[0] : pairOfArrays[1]
      targetArray.push(item)
      return pairOfArrays
    },
    [[], []],
  )
}
