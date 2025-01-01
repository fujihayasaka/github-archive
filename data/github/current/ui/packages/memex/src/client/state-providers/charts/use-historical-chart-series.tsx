import {omit} from '../../../utils/omit'
import type {MemexChartConfiguration} from '../../api/charts/contracts/api'
import type {FormattedChartSeries} from '../../api/insights/contracts'
import {styleForChartType} from '../../pages/insights/highcharts-theme'
import {useChartSeriesQuery} from '../../queries/use-chart-series-query'
import {getLeanInsightsColorCoding} from './use-lean-historical-chart-series'

function formatDates(dates: Array<string>) {
  const currentYear = new Date().getUTCFullYear()

  const excludeYearFormat = Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  })

  const includeYearFormat = Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    timeZone: 'UTC',
  })

  return dates.map(date => {
    const parsedDate = new Date(date)
    const isCurrentYear = parsedDate.getUTCFullYear() === currentYear
    return isCurrentYear ? excludeYearFormat.format(parsedDate) : includeYearFormat.format(parsedDate).replace(',', '')
  })
}

export function useHistoricalChartSeries({
  configuration,
  startDate,
  endDate,
}: {
  configuration: MemexChartConfiguration
  startDate?: string
  endDate?: string
}) {
  const {time} = configuration
  const chartConfiguration = time
    ? {...configuration, time: {...time, startDate, endDate}}
    : omit(configuration, ['time'])

  const chartQuery = useChartSeriesQuery(chartConfiguration)
  const isLoading = !chartQuery.data
  const chartType = configuration.type
  const series: FormattedChartSeries = (chartQuery.data?.dataSeries || []).map(s => {
    const colorSet = getLeanInsightsColorCoding()?.[s.name]
    const style = colorSet ? styleForChartType(chartType, colorSet) : {}

    return {
      ...s,
      ...style,
    }
  })

  const xCoordinates = formatDates(chartQuery.data?.xAxis.values || [])
  return {
    series,
    xCoordinates,
    isLoading,
  }
}
