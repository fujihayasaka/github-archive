import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQuery} from '../../../common/hooks/use-config-query'
import {fetchJson} from '../../../common/utils/fetch-json'

interface AlertsFixedResult {
  count: number
  matching: number
  percentage: number
}

export interface UseAlertsFixedQueryParams {
  query: string
}
export default function useAlertsFixedQuery({query}: UseAlertsFixedQueryParams): UseQueryResult<AlertsFixedResult> {
  const paths = usePaths()
  const path = paths.dependabotAlertsFixedPath({
    query,
  })

  return useQuery({
    queryKey: [path],
    queryFn: () => fetchJson(path),
  })
}
