import type {QueryClient} from '@tanstack/react-query'

import {buildFieldMetricsQueryKey} from '../queries/query-keys'
import type {FieldMetricsQueryData, PaginatedMemexItemsQueryVariables} from '../queries/types'

/**
 * A wrapper around setQueryData for setting field metrics data for a view,
 * that also merges the new query data with the existing groups. So, if there is already
 * data for 'group1', it will remain in the query data, even if a key for group1 is not in
 * the newQueryData parameter. If the key exists in both the existing and new query data,
 * the value from the new query data parameter is honored.

 * @param queryClient
 * @param variables PaginatedMemexItemsQueryVariables used in the query key
 * @param queryData The new field metrics data
 */
export function mergeFieldMetricsQueryData(
  queryClient: QueryClient,
  variables: PaginatedMemexItemsQueryVariables,
  newQueryData: FieldMetricsQueryData,
) {
  const queryKey = buildFieldMetricsQueryKey(variables)
  queryClient.setQueryData<FieldMetricsQueryData>(queryKey, queryData => {
    const mergedQueryData: FieldMetricsQueryData = {
      groups: {...queryData?.groups, ...newQueryData.groups},
    }

    return mergedQueryData
  })
}
