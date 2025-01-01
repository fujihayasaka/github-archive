import {testIdProps} from '@github-ui/test-id-props'
import {memo} from 'react'
import type {ColumnInstance} from 'react-table'

import type {MemexItemModel} from '../../models/memex-item-model'
import {
  type GroupId,
  isPageTypeForGroupedItems,
  type PageType,
  pageTypeForGroups,
  pageTypeForUngroupedItems,
} from '../../state-providers/memex-items/queries/query-keys'
import {
  useGroupsVisiblePagination,
  useSinglyGroupedItemsVisiblePagination,
  useUngroupedVisiblePagination,
} from '../common/use-visible-pagination'
import {StyledTableCell} from './table-cell'
import {useTableInstance} from './table-provider'
import {StyledTableRow, tableRowStyle} from './table-row'

export const PLACEHOLDER_ROW_COUNT = 5

export const TablePagination: React.FC<{pageType: PageType}> = ({pageType}) => {
  if (pageType === pageTypeForUngroupedItems) {
    return <UngroupedPagination />
  } else if (pageType === pageTypeForGroups) {
    return <GroupsPagination />
  } else if (isPageTypeForGroupedItems(pageType)) {
    return <GroupedItemsPagination groupId={pageType.groupId} />
  } else {
    // The table view doesn't support grouped item batches or secondary groups
    return null
  }
}

const UngroupedPagination: React.FC = () => {
  const {ref, hasNextPage} = useUngroupedVisiblePagination()
  const {visibleColumns} = useTableInstance()
  return (
    <div ref={ref} {...testIdProps(`table-pagination`)}>
      {!hasNextPage
        ? null
        : [...Array(PLACEHOLDER_ROW_COUNT).keys()].map(key => <PlaceholderRow key={key} columns={visibleColumns} />)}
    </div>
  )
}

const GroupsPagination: React.FC = () => {
  const {ref, hasNextPage} = useGroupsVisiblePagination()
  const {visibleColumns} = useTableInstance()
  return (
    <div ref={ref} {...testIdProps(`table-pagination`)}>
      {!hasNextPage
        ? null
        : [...Array(PLACEHOLDER_ROW_COUNT).keys()].map(key => <PlaceholderRow key={key} columns={visibleColumns} />)}
    </div>
  )
}

const GroupedItemsPagination: React.FC<{groupId: GroupId}> = ({groupId}) => {
  const {ref, hasNextPage} = useSinglyGroupedItemsVisiblePagination(groupId)
  const {visibleColumns} = useTableInstance()
  return (
    <div ref={ref} {...testIdProps(`table-pagination-${groupId}`)}>
      {!hasNextPage
        ? null
        : [...Array(PLACEHOLDER_ROW_COUNT).keys()].map(key => <PlaceholderRow key={key} columns={visibleColumns} />)}
    </div>
  )
}

type PlaceholderRowProps = {
  columns: Array<ColumnInstance<MemexItemModel>>
}

const PlaceholderRowUnmemoized: React.FC<PlaceholderRowProps> = ({columns}) => {
  return (
    <StyledTableRow role="row" style={{...tableRowStyle}} {...testIdProps('placeholder-row')}>
      {columns.map(column => (
        <StyledTableCell key={column.id} role="gridcell" style={{whiteSpace: 'nowrap', width: column.width}}>
          {column.Placeholder}
        </StyledTableCell>
      ))}
    </StyledTableRow>
  )
}

const PlaceholderRow = memo(PlaceholderRowUnmemoized)
