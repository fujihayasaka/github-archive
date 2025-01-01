import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQuery} from '../../../common/hooks/use-config-query'
import {fetchJson} from '../../../common/utils/fetch-json'

interface AlertsFixedResult {
  count: number
  total: number
  percentage: number
}

export interface UseAlertsFixedQueryParams {
  query: string
  startDate: string
  endDate: string
}
export default function useAlertsFixedQuery({
  query,
  startDate,
  endDate,
}: UseAlertsFixedQueryParams): UseQueryResult<AlertsFixedResult> {
  const paths = usePaths()
  const path = paths.codeScanningAlertsFixedPath({
    query,
    startDate,
    endDate,
  })

  return useQuery({
    queryKey: [path],
    queryFn: () => fetchJson(path),
  })
}
