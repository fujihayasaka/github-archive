import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {useCallback} from 'react'
import {useListViewSelection} from '@github-ui/list-view/ListViewSelectionContext'
import {useListViewMultiPageSelection} from '@github-ui/list-view/ListViewMultiPageSelectionContext'

import type {ListItemsHeaderProps} from '../types'

import {LABELS} from '../constants/labels'
export const ListItemsHeaderWithoutBulkActions = ({
  sectionFilters,
  issueNodes,
  setCheckedItems,
  updateListHasPRs,
  ...rest
}: ListItemsHeaderProps) => {
  const {setSelectedCount} = useListViewSelection()
  const {setMultiPageSelectionAllowed} = useListViewMultiPageSelection()
  const onToggleSelectAll = useCallback(
    (isSelectAllChecked: boolean) => {
      if (isSelectAllChecked) {
        setCheckedItems(
          issueNodes.filter(node => node != null).reduce((map, node) => map.set(node.id, node), new Map()),
        )
        updateListHasPRs(
          issueNodes.filter(node => node != null).reduce((map, node) => map.set(node.id, node), new Map()),
        )
      } else {
        setCheckedItems(new Map())
        setSelectedCount(0)
        setMultiPageSelectionAllowed?.(false)
      }
    },
    [issueNodes, setCheckedItems, setMultiPageSelectionAllowed, setSelectedCount, updateListHasPRs],
  )
  return (
    <ListViewMetadata
      onToggleSelectAll={onToggleSelectAll}
      actionsLabel={LABELS.bulkActions}
      actions={[]}
      sectionFilters={sectionFilters}
      density={'normal'}
      {...rest}
    />
  )
}
