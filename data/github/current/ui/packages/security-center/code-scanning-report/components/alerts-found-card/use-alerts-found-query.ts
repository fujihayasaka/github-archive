import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQuery} from '../../../common/hooks/use-config-query'
import {fetchJson} from '../../../common/utils/fetch-json'

interface AlertsFoundResult {
  count: number
}

export interface UseAlertsFoundQueryParams {
  query: string
  startDate: string
  endDate: string
}
export default function useAlertsFoundQuery({
  query,
  startDate,
  endDate,
}: UseAlertsFoundQueryParams): UseQueryResult<AlertsFoundResult> {
  const paths = usePaths()
  const path = paths.codeScanningAlertsFoundPath({
    query,
    startDate,
    endDate,
  })

  return useQuery({
    queryKey: [path],
    queryFn: () => fetchJson(path),
  })
}
