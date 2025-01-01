import {useQuery, type UseQueryResult} from '@tanstack/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {fetchJson} from '../../../common/utils/fetch-json'

interface AlertsFixedInPullRequestsResult {
  count: number
  total: number
  percentage: number
}

export interface UseAlertsFixedInPullRequestsQueryParams {
  query: string
  startDate: string
  endDate: string
}
export default function useAlertsFixedInPullRequestsQuery({
  query,
  startDate,
  endDate,
}: UseAlertsFixedInPullRequestsQueryParams): UseQueryResult<AlertsFixedInPullRequestsResult> {
  const paths = usePaths()
  const path = paths.pullRequestAlertsFixedPath({
    query,
    startDate,
    endDate,
  })

  return useQuery({
    queryKey: [path],
    queryFn: () => fetchJson(path),
  })
}
