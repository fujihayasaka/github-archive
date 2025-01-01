import {useQuery, type UseQueryResult} from '@tanstack/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {fetchJson} from '../../../common/utils/fetch-json'
import type {GroupKey} from './GroupMenu'

export type AlertTrendsResult = Array<{
  label: string
  data: Array<{
    x: string
    y: number
  }>
}>

interface UseAlertTrendsQueryParams {
  query: string
  startDate: string
  endDate: string
  groupKey: GroupKey
}
export function useAlertTrendsQuery({
  query,
  startDate,
  endDate,
  groupKey,
}: UseAlertTrendsQueryParams): UseQueryResult<AlertTrendsResult> {
  const paths = usePaths()
  const path = paths.codeScanningAlertTrendsPath({
    groupKey,
    query,
    startDate,
    endDate,
  })

  return useQuery({
    queryKey: [path],
    queryFn: () => fetchJson(path),
  })
}
