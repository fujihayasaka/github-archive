import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQuery} from '../../../common/hooks/use-config-query'
import {fetchJson} from '../../../common/utils/fetch-json'

interface AlertsFixedWithAutofixResult {
  accepted: number
  suggested: number
}

export interface UseAlertsFixedWithAutofixQueryParams {
  query: string
  startDate: string
  endDate: string
}
export default function useAlertsFixedWithAutofixQuery({
  query,
  startDate,
  endDate,
}: UseAlertsFixedWithAutofixQueryParams): UseQueryResult<AlertsFixedWithAutofixResult> {
  const paths = usePaths()
  const path = paths.codeScanningAlertsFixedWithAutofixPath({
    query,
    startDate,
    endDate,
  })

  return useQuery({
    queryKey: [path],
    queryFn: () => fetchJson(path),
  })
}
