import {queryOptions, useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import type {Workbenches} from '../utils/spark-types'

export const workbenchesQueryOptions = queryOptions({
  queryKey: ['workbenches'],
  queryFn: async () => {
    const res = await verifiedFetchJSON('/copilot/spark/workbench', {method: 'GET'})
    if (res.ok) {
      const data = (await res.json()) as Workbenches
      return data.workbenches
    }
    return []
  },
})

export const useWorkbenchesQuery = () => {
  return useQuery(workbenchesQueryOptions)
}
