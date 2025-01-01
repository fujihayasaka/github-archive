import {useQuery, type UseQueryResult} from '@tanstack/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {fetchJson} from '../../../common/utils/fetch-json'

interface PullRequestAlertsFixedWithAutofixResult {
  accepted: number
  suggested: number
}

export interface UsePullRequestAlertsFixedWithAutofixQueryParams {
  query: string
  startDate: string
  endDate: string
}
export default function usePullRequestAlertsFixedWithAutofixQuery({
  query,
  startDate,
  endDate,
}: UsePullRequestAlertsFixedWithAutofixQueryParams): UseQueryResult<PullRequestAlertsFixedWithAutofixResult> {
  const paths = usePaths()
  const path = paths.alertsFixedWithAutofixPath({
    query,
    startDate,
    endDate,
  })

  return useQuery({
    queryKey: [path],
    queryFn: () => fetchJson(path),
  })
}
