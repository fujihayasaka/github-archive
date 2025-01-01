import {queryOptions, useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import type {Workbenches} from '../utils/spark-types'

export const favoriteWorkbenchesQueryOptions = queryOptions({
  queryKey: ['workbenches', 'favorites'],
  queryFn: async () => {
    const res = await verifiedFetchJSON('/spark/favorites', {method: 'GET'})
    if (res.ok) {
      const data = (await res.json()) as Workbenches
      return data.workbenches
    }
    return []
  },
})

export const useFavoriteWorkbenchesQuery = () => {
  return useQuery(favoriteWorkbenchesQueryOptions)
}
