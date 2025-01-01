import {useMemo} from 'react'
import type {Theme, BaseColumnChartProps, ColumnChartProps, ColumnChartStyles} from '../types'
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

export const getTheme = (color: Theme): Array<string | Highcharts.GradientColorObject> => [
  `var(--display-${color}-scale-9)`,
  `var(--display-${color}-scale-5)`,
  {
    linearGradient: {
      x1: 0,
      x2: 0,
      y1: 1,
      y2: 0,
    },
    stops: [
      [0.15, `var(--display-${color}-scale-0)`],
      [0.75, `var(--display-${color}-scale-2)`],
      [1, `var(--display-${color}-scale-4)`],
    ],
  },
  {
    linearGradient: {
      x1: 0,
      x2: 0,
      y1: 1,
      y2: 0,
    },
    stops: [
      [0.0, 'var(--bgColor-default)'],
      [0.5, `var(--display-${color}-scale-0)`],
      [1, `var(--display-${color}-scale-1)`],
    ],
  },
  `var(--display-${color}-scale-0)`,
]

export const getThemeBySeriesCount = (seriesCount: number, theme: Theme) => {
  return getTheme(theme).slice(0, seriesCount).reverse()
}

export const getColumnChartTheme = (theme: Theme): Array<string | Highcharts.GradientColorObject> => {
  return getThemeBySeriesCount(MAX_NUMBER_OF_SERIES_ITEMS, theme)
}

export const ColumnDefaultColor = {
  pine: MarkColor.pine,
  teal: MarkColor.teal,
  cyan: MarkColor.cyan,
  blue: MarkColor.blue,
  indigo: MarkColor.indigo,
  purple: MarkColor.purple,
  orange: MarkColor.orange,
}

export const BaseColumnChart = <T extends 'bar' | 'column'>({
  type,
  options,
  series: data,
  stacking,
  labels,
  colors,
  theme: userTheme,
  ...rest
}: BaseColumnChartProps<T> & ColumnChartStyles) => {
  const {xAxis, yAxis, plot} = options ?? {}
  const xyAxisOptionsTransformed = useMemo(() => getXAxisOptionWithDefaults({xAxis, gridLineWidth: 0}), [xAxis])
  const theme = useMemo(() => getThemeBySeriesCount(data?.length ?? 0, userTheme ?? 'green'), [userTheme, data])

  const yAxisOptionsTransformed = useMemo(
    () => getYAxisOptionsWithDefaults({yAxis, gridLineDashStyle: 'Dash'}),
    [yAxis],
  )
  const seriesWithBorder = useMemo(() => {
    return data?.map((series, idx) => {
      if (stacking && series.colorByPoint) {
        // eslint-disable-next-line no-console
        console.warn('Stacking is enabled, colorByPoint will be set to false for all series.')
      }

      const is3rd = JSON.stringify(theme[idx]) === JSON.stringify(getTheme(userTheme ?? 'green')[3])
      const is4th = theme[idx] === getTheme(userTheme ?? 'green')[4]

      return {
        ...series,
        colorByPoint: stacking ? false : series.colorByPoint,
        dashStyle: is3rd ? 'ShortDash' : is4th ? 'Solid' : undefined,
        borderColor: is3rd
          ? `var(--display-${userTheme ?? 'green'}-scale-4)`
          : is4th
            ? `var(--display-${userTheme ?? 'green'}-scale-4)`
            : undefined,
      }
    })
  }, [data, stacking, theme, userTheme])

  const series = useMemo(
    () =>
      getDataWithDefaults({
        series: seriesWithBorder as Highcharts.SeriesOptionsType[],
        type,
        hasDashStyle: false,
      }),
    [seriesWithBorder, type],
  )

  const plotOptionsTransformed = useMemo(
    () => getTransformedPlotOptions({plotOptions: plot, labels, stacking, noBorderRadius: true}),
    [labels, stacking, plot],
  )

  if (series.length > MAX_NUMBER_OF_SERIES_ITEMS && isDev()) {
    // eslint-disable-next-line no-console
    console.error('Ideally, a column chart should contain no more than 5 segments or columns.')
  }

  return (
    <Chart
      type={type}
      xAxisOptions={xyAxisOptionsTransformed}
      yAxisOptions={yAxisOptionsTransformed}
      series={series as Highcharts.SeriesOptionsType[]}
      plotOptions={plotOptionsTransformed}
      colors={
        stacking && series.length > 1
          ? theme
          : colors
            ? colors.map((color: keyof typeof MarkColor) => `var(${MarkColor[color]})`)
            : Object.keys(ColumnDefaultColor).map(
                key => `var(${ColumnDefaultColor[key as keyof typeof ColumnDefaultColor]})`,
              )
      }
      {...rest}
    />
  )
}

const ColumnChart = (props: ColumnChartProps) => {
  return <BaseColumnChart {...props} type="column" />
}

export default ColumnChart
