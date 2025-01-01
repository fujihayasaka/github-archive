import {useMemo} from 'react'
import type {LineChartProps, BaseLineChartProps} from '../types'
import {MarkColor} from '../types'
import Chart from '../Chart'
import {
  getDataWithDefaults,
  getTransformedPlotOptions,
  getXAxisOptionWithDefaults,
  getYAxisOptionsWithDefaults,
  isDev,
} from './shared'

const MAX_NUMBER_OF_SERIES_ITEMS = 11

export const LineDefaultColor = {
  green: MarkColor.green,
  blue: MarkColor.blue,
  olive: MarkColor.olive,
  indigo: MarkColor.indigo,
  teal: MarkColor.teal,
  orange: MarkColor.orange,
  yellow: MarkColor.yellow,
  red: MarkColor.red,
  pink: MarkColor.pink,
  plum: MarkColor.plum,
  purple: MarkColor.purple,
}

export const BaseLineChart = <T extends 'line' | 'spline'>({
  type,
  options,
  series: data,
  marker,
  labels,
  ...rest
}: BaseLineChartProps<T>) => {
  const {xAxis, yAxis, plot} = options ?? {}
  const xyAxisOptionsTransformed = useMemo(
    () => getXAxisOptionWithDefaults({xAxis, gridLineDashStyle: 'Solid'}),
    [xAxis],
  )
  const yAxisOptionsTransformed = useMemo(
    () => getYAxisOptionsWithDefaults({yAxis, gridLineDashStyle: 'Solid'}),
    [yAxis],
  )
  const seriesWithColors = useMemo(() => {
    return data?.map((s, index) => {
      const keys = Object.keys(LineDefaultColor) as Array<keyof typeof LineDefaultColor>
      const colorKey = keys[index % keys.length]
      return {
        ...s,
        color: s.color ? `var(${MarkColor[s.color]})` : colorKey ? `var(${LineDefaultColor[colorKey]})` : undefined,
      }
    })
  }, [data])

  const series = useMemo(
    () => getDataWithDefaults({series: seriesWithColors as Highcharts.SeriesOptionsType[], type}),
    [seriesWithColors, type],
  )

  const plotOptionsTransformed = useMemo(
    () => getTransformedPlotOptions({plotOptions: plot, marker, labels}),
    [plot, marker, labels],
  )

  if (series.length > MAX_NUMBER_OF_SERIES_ITEMS && isDev()) {
    // eslint-disable-next-line no-console
    console.error('Ideally, a line chart should contain no more than 11 lines.')
  }

  return (
    <Chart
      type={type}
      xAxisOptions={xyAxisOptionsTransformed}
      yAxisOptions={yAxisOptionsTransformed}
      series={series as Highcharts.SeriesOptionsType[]}
      plotOptions={plotOptionsTransformed}
      {...rest}
    />
  )
}

const LineChart = (props: LineChartProps) => {
  return <BaseLineChart {...props} type="line" />
}

export default LineChart
