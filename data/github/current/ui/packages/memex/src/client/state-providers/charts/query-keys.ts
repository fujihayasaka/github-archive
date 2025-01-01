import pickBy from 'lodash-es/pickBy'

import {identity} from '../../../utils/identity'
import type {MemexChartConfiguration} from '../../api/charts/contracts/api'
import type {GetChartRequest} from '../../api/insights/contracts'

export const chartSeriesQueryKey = 'chart-series-data'

export type ChartQueryKey = ['memex', typeof chartSeriesQueryKey]
export type ChartRequestQueryKey = ['memex', typeof chartSeriesQueryKey, GetChartRequest]

export function buildChartQueryKey(configuration: MemexChartConfiguration): ChartRequestQueryKey {
  return ['memex', chartSeriesQueryKey, buildChartSeriesRequest(configuration)]
}

export function buildChartSeriesRequest(configuration: MemexChartConfiguration): GetChartRequest {
  const {filter, xAxis, yAxis} = configuration
  const {period, startDate, endDate} = xAxis.dataSource.column === 'time' ? configuration.time ?? {} : {}

  if (xAxis.dataSource.column === 'time' && xAxis.groupBy) {
    // Remove `groupBy` from historical requests only! We still generate the configuration with `groupBy` from the days
    // when historical charts supported this feature while querying the now-decommissioned Insights Platform.
    delete xAxis.groupBy
  }

  // Include only truthy key value pairs for the final request payload
  return {xAxis, yAxis, ...pickBy({filter, period, startDate, endDate}, identity)}
}
