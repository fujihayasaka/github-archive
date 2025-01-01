import {useQueryClient, type UseQueryResult} from '@tanstack/react-query'
import {useCallback, useMemo} from 'react'

import {NO_GROUP_VALUE} from '../../../api/memex-items/contracts'
import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import type {ColumnModel} from '../../../models/column-model'
import {
  getVerticalGroupsForField,
  isVerticalGroupMetadata,
  MissingVerticalGroupId,
  type VerticalGroup,
} from '../../../models/vertical-group'
import {useAllColumns} from '../../../state-providers/columns/use-all-columns'
import type {MemexGroupsPageQueryData} from '../../../state-providers/memex-items/queries/types'
import {usePaginatedMemexItemsQuery} from '../../../state-providers/memex-items/queries/use-paginated-memex-items-query'
import {getServerGroupIdForVerticalGroupId} from '../../../state-providers/memex-items/query-client-api/memex-groups'
import {useFilteredGroups} from './use-filtered-groups'
import {useVerticalGroupedBy} from './use-vertical-grouped-by'

/**
 * Calls the useFilteredGroups hook with the current vertical grouping field, as well as
 * a function for determining the list of groups for a given field.
 * @returns An array of groups, or undefined if no grouping is currently active.
 */
export const useVerticalGroups = () => {
  const {groupedByColumnId} = useVerticalGroupedBy()
  const {allColumns} = useAllColumns()
  const groupByField = allColumns.find(c => c.id === groupedByColumnId)
  const queryClient = useQueryClient()

  const {memex_table_without_limits} = useEnabledFeatures()

  // Feature flags will not change after initial render
  // eslint-disable-next-line react-hooks/react-compiler
  // eslint-disable-next-line react-hooks/rules-of-hooks
  const {queriesForGroups} = memex_table_without_limits ? usePaginatedMemexItemsQuery() : {queriesForGroups: []}
  const getGroupIdForVerticalGroupId = memex_table_without_limits
    ? // eslint-disable-next-line react-hooks/react-compiler
      // eslint-disable-next-line react-hooks/rules-of-hooks
      useCallback(
        (verticalGroupId: VerticalGroup['id']) => {
          // TODO: This helper won't be needed once the board
          // no longer depends on MissingVerticalGroupId
          // https://github.com/github/projects-platform/issues/2127
          return getServerGroupIdForVerticalGroupId(queryClient, verticalGroupId)
        },
        [queryClient],
      )
    : undefined

  const {getGroupByFieldOptions} = useFilteredGroups()

  return useMemo(() => {
    let groupByFieldOptions: Array<VerticalGroup> | undefined = undefined
    if (groupByField && memex_table_without_limits) {
      groupByFieldOptions = getServerVerticalGroups(groupByField, queriesForGroups)
    } else if (groupByField) {
      groupByFieldOptions = getGroupByFieldOptions(groupByField, getVerticalGroupsForField)
    }
    return {groupByFieldOptions, groupedByColumnId, getServerGroupIdForVerticalGroupId: getGroupIdForVerticalGroupId}
  }, [
    getGroupByFieldOptions,
    getGroupIdForVerticalGroupId,
    groupByField,
    groupedByColumnId,
    queriesForGroups,
    memex_table_without_limits,
  ])
}

const getServerVerticalGroups = (
  groupByField: ColumnModel,
  queriesForGroups: Array<UseQueryResult<MemexGroupsPageQueryData>>,
) => {
  const serverGroups = queriesForGroups.flatMap(q => q.data?.groups ?? [])
  const groups = serverGroups.map(group => {
    const isNoValueGroup = group.groupValue === NO_GROUP_VALUE
    const name = isNoValueGroup ? `No ${groupByField.name}` : group.groupValue
    const groupMetadata = isVerticalGroupMetadata(group.groupMetadata) ? group.groupMetadata : undefined
    return {
      // TODO: Remove dependence on MissingVerticalGroupId
      // https://github.com/github/projects-platform/issues/2127
      id: isNoValueGroup ? MissingVerticalGroupId : group.groupId,
      name,
      nameHtml: name, // TODO - move nameHtml to groupMetadata
      groupMetadata,
    }
  })
  return groups
}
