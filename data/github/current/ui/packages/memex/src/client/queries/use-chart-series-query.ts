import {useQuery} from '@tanstack/react-query'

import type {MemexChartConfiguration} from '../api/charts/contracts/api'
import {apiGetChart} from '../api/insights/api-get-chart'
import {buildChartQueryKey, buildChartSeriesRequest} from '../state-providers/charts/query-keys'

export function useChartSeriesQuery(configuration: MemexChartConfiguration) {
  const query = useQuery({
    queryKey: buildChartQueryKey(configuration),
    queryFn: async () => {
      return apiGetChart(buildChartSeriesRequest(configuration))
    },
    staleTime: Infinity,
  })

  return query
}
