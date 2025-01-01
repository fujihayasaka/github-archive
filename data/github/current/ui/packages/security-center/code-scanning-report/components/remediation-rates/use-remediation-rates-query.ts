import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQuery} from '../../../common/hooks/use-config-query'
import {fetchJson} from '../../../common/utils/fetch-json'

interface RemediationRatesResult {
  percentFixedWithAutofixSuggested: number
  percentFixedWithNoAutofixSuggested: number
}

export interface UseRemediationRatesQueryParams {
  query: string
  startDate: string
  endDate: string
}
export default function useRemediationRatesQuery({
  query,
  startDate,
  endDate,
}: UseRemediationRatesQueryParams): UseQueryResult<RemediationRatesResult> {
  const paths = usePaths()
  const path = paths.codeScanningRemediationRatesPath({
    query,
    startDate,
    endDate,
  })

  return useQuery({
    queryKey: [path],
    queryFn: () => fetchJson(path),
  })
}
