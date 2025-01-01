import {useQuery} from '@tanstack/react-query'

import {apiGetPaginatedItems} from '../api/memex-items/api-get-paginated-items'
import type {ColumnModel} from '../models/column-model'

/**
 * Makes a request to the pagianted items endpoint with a query like
 * `-no:Priority` (when the field name is `Priority`) and returns the total count
 * from the response.
 */
export function useItemsWithFieldValueCountQuery(columnModel: ColumnModel) {
  return useQuery({
    queryKey: ['itemsWithFieldValue', columnModel.name],
    queryFn: async () => {
      const q = `has:${columnModel.name}`
      const response = await apiGetPaginatedItems({q, first: 1})
      return response.totalCount.value
    },
  })
}
