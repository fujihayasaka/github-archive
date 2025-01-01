import {useMemo} from 'react'
import type {BaseAreaChartProps, AreaChartProps} from '../types'
import {MarkColor} from '../types'
import {
  getDataWithDefaults,
  getTransformedPlotOptions,
  getXAxisOptionWithDefaults,
  getYAxisOptionsWithDefaults,
  isDev,
} from './shared'
import Chart from '../Chart'

const MAX_NUMBER_OF_SERIES_ITEMS = 5

export const AreaDefaultColor = {
  green: MarkColor.green,
  teal: MarkColor.teal,
  blue: MarkColor.blue,
  indigo: MarkColor.indigo,
  orange: MarkColor.orange,
}

export const AreaDefaultFillColor = {
  green: '--display-green-scale-0',
  teal: '--display-teal-scale-0',
  blue: '--display-blue-scale-0',
  indigo: '--display-indigo-scale-0',
  orange: '--display-orange-scale-0',
}

export const BaseAreaChart = <T extends 'area' | 'areaspline'>({
  type,
  options,
  series: data,
  stacking = 'normal',
  marker,
  labels,
  ...rest
}: BaseAreaChartProps<T>) => {
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
      const keys = Object.keys(AreaDefaultColor).filter(Boolean) as Array<keyof typeof AreaDefaultColor>
      const colorKey = keys[index % keys.length]
      return {
        ...s,
        color: s.color ? `var(${MarkColor[s.color]})` : colorKey ? `var(${AreaDefaultColor[colorKey]})` : undefined,
        fillColor: s.color ? undefined : colorKey ? `var(${AreaDefaultFillColor[colorKey]})` : undefined,
      }
    })
  }, [data])

  const series = useMemo(
    () => getDataWithDefaults({series: seriesWithColors as Highcharts.SeriesOptionsType[], type}),
    [seriesWithColors, type],
  )

  const plotOptionsTransformed = useMemo(
    () => getTransformedPlotOptions({plotOptions: plot, marker, labels, stacking}),
    [marker, labels, stacking, plot],
  )

  if (series.length > MAX_NUMBER_OF_SERIES_ITEMS && isDev()) {
    // eslint-disable-next-line no-console
    console.error('Ideally, an area chart should contain no more than 5 lines.')
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

const AreaChart = (props: AreaChartProps) => {
  return <BaseAreaChart {...props} type="area" />
}

export default AreaChart
