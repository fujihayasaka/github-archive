import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQuery} from '../../../common/hooks/use-config-query'
import {fetchJson} from '../../../common/utils/fetch-json'

interface RemediationTimeResult {
  remediationTimeInHoursWithAutofixSuggested: number
  remediationTimeInHoursWithNoAutofixSuggested: number
}

export interface UseRemediationTimeQueryParams {
  query: string
  startDate: string
  endDate: string
}
export default function useRemediationTimeQuery({
  query,
  startDate,
  endDate,
}: UseRemediationTimeQueryParams): UseQueryResult<RemediationTimeResult> {
  const paths = usePaths()
  const path = paths.codeScanningRemediationTimePath({
    query,
    startDate,
    endDate,
  })

  return useQuery({
    queryKey: [path],
    queryFn: () => fetchJson(path),
  })
}
