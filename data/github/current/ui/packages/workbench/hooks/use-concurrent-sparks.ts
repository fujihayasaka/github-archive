import {isFeatureEnabled} from '@github-ui/feature-flags'
import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useMemo} from 'react'

import type {Workbench} from '../types/workbench-types'

const fetchWorkbenches = async (): Promise<Workbench[]> => {
  const res = await verifiedFetchJSON('/copilot/spark/workbench.json')
  if (!res.ok) {
    throw new Error(`Failed to fetch workbenches: ${res.status} ${res.statusText}`)
  }
  const payload: {workbenches: Workbench[]} = await res.json()
  return payload.workbenches
}

const isActive = (item: Workbench): boolean => {
  return !!item.cloudspace_active
}

const getConcurrentSparks = (items: Workbench[]): Workbench[] => {
  // filter out inactive workbenches
  items = items.filter(isActive)

  return items
}

const getOldestActiveName = (items: Workbench[]): string | null => {
  // filter out inactive workbenches
  items = getConcurrentSparks(items)
  // filter out items with 'cloudspace_last_used_at' property that is not a string
  const itemsWithDate = items.filter(
    (item): item is Workbench & {cloudspace_last_used_at: string} => typeof item.cloudspace_last_used_at === 'string',
  )
  if (itemsWithDate.length === 0) return null

  // sort ascending by last_used
  const [oldest] = [...itemsWithDate].sort(
    (a, b) => new Date(a.cloudspace_last_used_at).getTime() - new Date(b.cloudspace_last_used_at).getTime(),
  )
  return oldest && oldest.cloudspace_name !== undefined ? oldest.cloudspace_name : null
}

export function useConcurrentSparks(): {
  oldestSparkName: string | null
  activeSparksCount: number
  activeSparks: Workbench[]
} | null {
  const {data} = useQuery<Workbench[]>({
    queryKey: ['oldest-active-spark'],
    queryFn: fetchWorkbenches,
    refetchInterval: 5 * 60 * 1000, // 5 minutes
  })

  const oldestActiveName = useMemo(() => (data ? getOldestActiveName(data) : null), [data])
  const count = useMemo(() => (data ? getConcurrentSparks(data).length : 0), [data])
  const activeSparks = useMemo(() => getConcurrentSparks(data ?? []), [data])

  if (!isFeatureEnabled('copilot_workbench_user_limits')) {
    return null
  }

  return {oldestSparkName: oldestActiveName, activeSparksCount: count, activeSparks}
}

export const MAXIMUM_INSTANCES_FOR_FREE_USERS = 1
export const MAXIMUM_INSTANCES_FOR_PAID_USERS = 10
