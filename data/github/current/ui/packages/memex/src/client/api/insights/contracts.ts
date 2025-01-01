import type {MemexChartConfiguration, MemexChartTime} from '../charts/contracts/api'

export type GetChartRequest = Pick<MemexChartConfiguration, 'xAxis'> &
  Partial<Pick<MemexChartConfiguration, 'filter'>> &
  Partial<Pick<MemexChartConfiguration, 'yAxis'>> &
  Partial<Pick<MemexChartTime, 'period' | 'startDate' | 'endDate'>>

export type DataSeriesDatum = {name: string; data: Array<number>}
export type DataSeries = Array<DataSeriesDatum>

export type GetChartResponse = {
  dataSeries: DataSeries
  xAxis: {values: Array<string>}
  totalCount: number
}

export type FormattedChartSeries = Array<
  GetChartResponse['dataSeries'][number] & {
    color?: string
    fillColor?: string
    borderColor?: string
    borderWidth?: number
  }
>
