import {InsightsResources} from '../../../client/strings'
import type {MemexChartConfiguration, MemexChartOperation} from '../../api/charts/contracts/api'
import type {DataSeries} from '../../api/insights/contracts'
import {isNumber} from '../../helpers/parsing'
import type {ColumnModel} from '../../models/column-model'
import {getYAxisAggregateLabel} from '../../pages/insights/components/insights-configuration-pane/y-axis-selector'
import {useChartSeriesQuery} from '../../queries/use-chart-series-query'
import {useFindColumnByDatabaseId} from '../columns/use-find-column-by-database-id'

export function getAxis(
  xAxisColumnModel?: ColumnModel,
  yAxisColumnModel?: ColumnModel,
  memexChartOperation?: MemexChartOperation,
) {
  const xAxis = {name: xAxisColumnModel?.name || 'Unknown', dataType: 'nvarchar'}
  let yAxis = {
    name: 'Count',
    dataType: 'int',
  }

  if (yAxisColumnModel && memexChartOperation && memexChartOperation !== 'count') {
    yAxis = {
      name: getYAxisAggregateLabel(memexChartOperation, yAxisColumnModel.name),
      dataType: 'int',
    }
  }

  return {xAxis, yAxis}
}

export function useChartSeries(configuration: MemexChartConfiguration) {
  const {findColumnByDatabaseId} = useFindColumnByDatabaseId()

  const {xAxis, yAxis} = configuration
  const xAxisColumn = xAxis.dataSource.column
  const xAxisGroupByColumn = xAxis.groupBy?.column
  const yAxisOperationColumn = yAxis.aggregate?.columns?.[0]
  const yAxisOperation = yAxis.aggregate?.operation

  const xAxisColumnModel = isNumber(xAxisColumn) ? findColumnByDatabaseId(xAxisColumn) : undefined
  const yAxisColumnModel = isNumber(yAxisOperationColumn) ? findColumnByDatabaseId(yAxisOperationColumn) : undefined
  const xAxisGroupByColumnModel = isNumber(xAxisGroupByColumn) ? findColumnByDatabaseId(xAxisGroupByColumn) : undefined

  const axis = getAxis(xAxisColumnModel, yAxisColumnModel, configuration.yAxis.aggregate.operation)

  const chartQuery = useChartSeriesQuery(configuration)
  const isLoading = !chartQuery.data

  let series: DataSeries = []
  let xCoordinates: Array<string> = []

  if (chartQuery.data && xAxisColumnModel?.name && chartQuery.data.dataSeries[0]) {
    const xAxisNoValue = InsightsResources.negateStr(xAxisColumnModel.name)

    xCoordinates = chartQuery.data.xAxis.values.map(v => (v === '_noValue' ? xAxisNoValue : v))

    // If grouped chart data, then replace the text of any _noValue group in the legend.
    // Otherwise, set the legend name similar to 'Count of Items' or 'Sum of Estimate'
    if (xAxisGroupByColumnModel) {
      const groupNoValue = InsightsResources.negateStr(xAxisGroupByColumnModel.name)
      series = chartQuery.data.dataSeries.map(d => (d.name === '_noValue' ? {...d, name: groupNoValue} : d))
    } else {
      const fieldName = yAxisColumnModel && yAxisOperation !== 'count' ? yAxisColumnModel.name : InsightsResources.items
      series = [{...chartQuery.data.dataSeries[0], name: getYAxisAggregateLabel(yAxisOperation, fieldName)}]
    }
  }

  return {
    series,
    axis,
    xCoordinates,
    isLoading,
  }
}
