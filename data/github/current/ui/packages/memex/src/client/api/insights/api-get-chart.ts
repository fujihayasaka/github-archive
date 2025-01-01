import {getApiMetadata} from '../../helpers/api-metadata'
import {fetchJSON} from '../../platform/functional-fetch-wrapper'
import {
  END_DATE_PARAM,
  FILTER_QUERY_PARAM,
  PERIOD_PARAM,
  START_DATE_PARAM,
  X_AXIS_DATASOURCE_COLUMN_PARAM,
  X_AXIS_DATASOURCE_SORT_ORDER_PARAM,
  X_AXIS_GROUP_BY_PARAM,
  Y_AXIS_AGGREGATE_COLUMNS_PARAM,
  Y_AXIS_AGGREGATE_OPERATION_PARAM,
} from '../../platform/url'
import type {GetChartRequest, GetChartResponse} from './contracts'

export async function apiGetChart({
  filter,
  xAxis,
  yAxis,
  startDate,
  endDate,
  period,
}: GetChartRequest): Promise<GetChartResponse> {
  const apiMetadata = getApiMetadata('memex-chart-show-api-data')

  const url = new URL(apiMetadata.url, window.location.origin)

  const filterQuery = filter
  const xAxisDataSourceColumn = xAxis.dataSource.column
  const xAxisDataSourceSortOrder = xAxis.dataSource.sortOrder
  const xAxisGroupBy = xAxis.groupBy?.column
  const yAxisAggregateOperation = yAxis?.aggregate.operation
  const yAxisAggregateColumns = yAxis?.aggregate.columns

  if (filterQuery) {
    url.searchParams.append(FILTER_QUERY_PARAM, filterQuery)
  }

  if (xAxisDataSourceColumn) {
    url.searchParams.append(X_AXIS_DATASOURCE_COLUMN_PARAM, xAxisDataSourceColumn.toString())
  }

  if (xAxisDataSourceSortOrder) {
    url.searchParams.append(X_AXIS_DATASOURCE_SORT_ORDER_PARAM, xAxisDataSourceSortOrder)
  }

  if (xAxisGroupBy) {
    url.searchParams.append(X_AXIS_GROUP_BY_PARAM, xAxisGroupBy.toString())
  }

  if (yAxisAggregateOperation) {
    url.searchParams.append(Y_AXIS_AGGREGATE_OPERATION_PARAM, yAxisAggregateOperation)
  }

  if (yAxisAggregateColumns) {
    url.searchParams.append(Y_AXIS_AGGREGATE_COLUMNS_PARAM, yAxisAggregateColumns.join(','))
  }

  if (startDate) {
    url.searchParams.append(START_DATE_PARAM, startDate)
  }

  if (endDate) {
    url.searchParams.append(END_DATE_PARAM, endDate)
  }

  if (period) {
    url.searchParams.append(PERIOD_PARAM, period)
  }

  const {data} = await fetchJSON<GetChartResponse>(url)
  return data
}
