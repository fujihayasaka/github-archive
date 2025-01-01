import {useQuery} from '@tanstack/react-query'

import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import {buildFieldMetricsQueryKey} from './query-keys'
import type {FieldMetricsQueryData} from './types'
import {usePaginatedMemexItemsQueryVariables} from './use-paginated-memex-items-query-variables'

export function useFieldMetricsQuery() {
  const {memex_table_without_limits} = useEnabledFeatures()

  if (memex_table_without_limits) {
    // eslint-disable-next-line react-hooks/react-compiler, react-hooks/rules-of-hooks
    return useFieldMetricsQueryPWLEnabled()
  }

  return undefined
}

function useFieldMetricsQueryPWLEnabled() {
  const variables = usePaginatedMemexItemsQueryVariables()
  const query = useQuery({
    queryKey: buildFieldMetricsQueryKey(variables),
    enabled: false,
    queryFn: () => {
      // We don't expect to use this queryFn, but by providing it we can
      // properly type the data returned by this query.
      return {groups: {}} as FieldMetricsQueryData
    },
  })

  return query
}
