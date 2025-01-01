import {useMemo} from 'react'

import {DefaultSearchConfig} from '../../../components/filter-bar/search-context'
import {useHorizontalGroupedBy} from '../../../features/grouping/hooks/use-horizontal-grouped-by'
import {useVerticalGroupedBy} from '../../../features/grouping/hooks/use-vertical-grouped-by'
import {useSliceBy} from '../../../features/slicing/hooks/use-slice-by'
import {ViewType} from '../../../helpers/view-type'
import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import {usePaginatedVariablesWithFieldIds} from '../../../hooks/use-paginated-variables-with-field-ids'
import {useSortedBy} from '../../../hooks/use-sorted-by'
import {useViews} from '../../../hooks/use-views'
import type {PaginatedMemexItemsQueryVariables} from './types'

export function usePaginatedMemexItemsQueryVariables(): PaginatedMemexItemsQueryVariables {
  const {memex_mwl_field_aggregations} = useEnabledFeatures()
  const {currentView} = useViews()
  const q = DefaultSearchConfig.getSearchQueryFromView(currentView)
  const {viewType, aggregationSettings} = currentView?.localViewStateDeserialized ?? {}
  const {sorts} = useSortedBy()
  const sortedBy = useMemo(
    () => sorts.map(sort => ({columnId: sort.column.databaseId, direction: sort.direction})),
    [sorts],
  )
  const {groupedByColumnId: horizontalGroupedByColumnId} = useHorizontalGroupedBy()
  let {groupedByColumnId: verticalGroupedByColumnId} = useVerticalGroupedBy()

  // only board views use vertical grouping, but it's always defaulted for any view type
  if (viewType !== ViewType.Board) {
    verticalGroupedByColumnId = undefined
  }

  const {sliceField, sliceValue} = useSliceBy()
  const sliceByColumnId = sliceField?.id

  const sumFields = useMemo(() => {
    return memex_mwl_field_aggregations ? aggregationSettings?.sum.map(f => f.id) : undefined
  }, [aggregationSettings?.sum, memex_mwl_field_aggregations])

  const variablesWithoutFieldIds: PaginatedMemexItemsQueryVariables = useMemo(
    () => ({
      q,
      sortedBy,
      viewType,
      horizontalGroupedByColumnId,
      verticalGroupedByColumnId,
      sliceByColumnId,
      // sliceValue can be `null`, which we want to coerce to undefined
      sliceByValue: sliceValue ?? undefined,
      sumFields,
    }),
    [
      q,
      sortedBy,
      viewType,
      horizontalGroupedByColumnId,
      verticalGroupedByColumnId,
      sliceByColumnId,
      sliceValue,
      sumFields,
    ],
  )

  return usePaginatedVariablesWithFieldIds(variablesWithoutFieldIds)
}
