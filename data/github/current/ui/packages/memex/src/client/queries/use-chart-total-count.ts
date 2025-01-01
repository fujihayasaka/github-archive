import type {MemexChartConfiguration} from '../api/charts/contracts/api'
import {useChartSeriesQuery} from './use-chart-series-query'

export function useChartTotalCount(configuration: MemexChartConfiguration) {
  const chartQuery = useChartSeriesQuery(configuration)

  // For feature parity with non-MWL projects, do not show the matching document count unless a filter is applied
  const filterCount = configuration.filter?.trim() ? chartQuery.data?.totalCount : undefined
  return {filterCount}
}
