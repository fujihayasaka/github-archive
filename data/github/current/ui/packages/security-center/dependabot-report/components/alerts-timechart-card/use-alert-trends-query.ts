import type {UseQueryResult} from '@github-ui/react-query'

import {usePaths} from '../../../common/contexts/Paths'
import {useQuery} from '../../../common/hooks/use-config-query'
import {fetchJson} from '../../../common/utils/fetch-json'

export type AlertTrendsResult = {
  label: string
  points: Array<{
    x: string
    y: number
  }>
}

interface UseAlertTrendsQueryParams {
  query: string
  funnelOrder?: string
}

export function useAlertTrendsQuery({
  query,
  funnelOrder,
}: UseAlertTrendsQueryParams): UseQueryResult<AlertTrendsResult> {
  const paths = usePaths()
  const path = paths.dependabotAlertTrendsPath({
    query,
    funnelOrder,
  })

  return useQuery({
    queryKey: [path],
    queryFn: () => fetchJson(path),
  })
}
