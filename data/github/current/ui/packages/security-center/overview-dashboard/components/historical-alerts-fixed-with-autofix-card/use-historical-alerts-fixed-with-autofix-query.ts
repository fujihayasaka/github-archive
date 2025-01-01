import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQuery} from '../../../common/hooks/use-config-query'
import {fetchJson} from '../../../common/utils/fetch-json'

interface HistoricalAlertsFixedWithAutofixResult {
  accepted: number
  suggested: number
}

export interface UseHistoricalAlertsFixedWithAutofixQueryParams {
  query: string
  startDate: string
  endDate: string
}
export default function useHistoricalAlertsFixedWithAutofixQuery({
  query,
  startDate,
  endDate,
}: UseHistoricalAlertsFixedWithAutofixQueryParams): UseQueryResult<HistoricalAlertsFixedWithAutofixResult> {
  const paths = usePaths()
  const path = paths.historicalAlertsFixedWithAutofixPath({
    query,
    startDate,
    endDate,
  })

  return useQuery({
    queryKey: [path],
    queryFn: () => fetchJson(path),
  })
}
