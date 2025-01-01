import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQuery} from '../../../common/hooks/use-config-query'
import {fetchJson} from '../../../common/utils/fetch-json'

interface AutofixSuggestionsResult {
  count: number
  percentage: number
}

export interface UseAutofixSuggestionsQueryParams {
  query: string
  startDate: string
  endDate: string
}
export default function useAutofixSuggestionsQuery({
  query,
  startDate,
  endDate,
}: UseAutofixSuggestionsQueryParams): UseQueryResult<AutofixSuggestionsResult> {
  const paths = usePaths()
  const path = paths.codeScanningAutofixSuggestionsPath({
    query,
    startDate,
    endDate,
  })

  return useQuery({
    queryKey: [path],
    queryFn: () => fetchJson(path),
  })
}
