import type {QueryClient} from '@tanstack/react-query'

import {buildSliceDataQueryKey} from '../queries/query-keys'
import type {PaginatedMemexItemsQueryVariables, SliceByQueryData} from '../queries/types'

export function setSliceByQueryData(
  queryClient: QueryClient,
  variables: PaginatedMemexItemsQueryVariables,
  queryData: SliceByQueryData,
) {
  queryClient.setQueryData(buildSliceDataQueryKey(variables), queryData)
}
