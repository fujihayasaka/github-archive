import Highcharts, {type Options} from 'highcharts'
import Highstock from 'highcharts/highstock'
import highchartsAccessibility from 'highcharts/modules/accessibility'
import highchartsExportData from 'highcharts/modules/export-data'
import highchartsExporting from 'highcharts/modules/exporting'
import highchartsOfflineExporting from 'highcharts/modules/offline-exporting'
import HighchartsReactOfficial from 'highcharts-react-official'
import merge from 'lodash-es/merge'
import defaultOptions, {yAxisConfig} from './chart-theme'
import ChartCardContext from './context'
import {useContext, useMemo} from 'react'
import type {Size} from '../shared'

// Init Highcharts modules
highchartsAccessibility(Highcharts)
highchartsExportData(Highcharts)
highchartsExporting(Highcharts)
highchartsOfflineExporting(Highcharts)

// Init Highstock modules
highchartsAccessibility(Highstock)
highchartsExportData(Highstock)
highchartsExporting(Highstock)
highchartsOfflineExporting(Highstock)

Highcharts.setOptions({
  lang: {
    decimalPoint: '.',
    thousandsSep: ',',
  },
})

Highstock.setOptions({
  lang: {
    decimalPoint: '.',
    thousandsSep: ',',
  },
})

export const chartHeights: {[size in Size]: string} = {
  xl: '432px',
  large: '320px',
  medium: '256px',
  small: '128px',
  sparkline: '128px',
}

export interface ChartProps {
  colors?: string[]
  overrideOptionsNotRecommended?: Highcharts.Options
  plotOptions?: Highcharts.PlotOptions
  series: Highcharts.SeriesOptionsType[]
  type: string
  xAxisTitle: string
  xAxisOptions?: Highcharts.XAxisOptions
  yAxisTitle?: string
  yAxisOptions?: Highcharts.YAxisOptions | Highcharts.YAxisOptions[]
  tooltipOptions?: Highcharts.TooltipOptions
  useUTC?: boolean
  showRangeSelector?: boolean
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function hasPropertyWithValue(obj: Record<string, any>, key: string, value: string) {
  if (typeof obj !== 'object' || obj === null) {
    return false
  }
  if (obj[key] === value) {
    return true
  } else {
    for (const prop in obj) {
      if (obj[prop] !== undefined) {
        return hasPropertyWithValue(obj[prop], key, value)
      }
    }
  }
  return false
}

export function Chart({
  // Scalar props
  type = 'line',
  xAxisTitle,
  yAxisTitle,
  useUTC = true,
  showRangeSelector = false,
  // Array/object props
  colors: _colors,
  plotOptions: _plotOptions,
  series: _series,
  xAxisOptions: _xAxisOptions,
  yAxisOptions: _yAxisOptions,
  tooltipOptions: _tooltipOptions,
  overrideOptionsNotRecommended: _overrideOptionsNotRecommended,
}: ChartProps) {
  // Get context
  const {title, description, size, chartRef} = useContext(ChartCardContext)

  // Stabilize array/object props
  // React hooks like `useMemo` check dependencies for reference equality. The following lines ensure object references only change when the object values change.
  const colors = useMemo(() => _colors, [_colors])
  const plotOptions = useMemo(() => _plotOptions, [_plotOptions])
  const series = useMemo(() => _series, [_series])
  const xAxisOptions = useMemo(() => _xAxisOptions ?? [], [_xAxisOptions])
  const yAxisOptions = useMemo(() => _yAxisOptions ?? [], [_yAxisOptions])
  const tooltipOptions = useMemo(() => _tooltipOptions, [_tooltipOptions])
  const overrideOptionsNotRecommended = useMemo(() => _overrideOptionsNotRecommended, [_overrideOptionsNotRecommended])

  // Get scalar derived values
  // These don’t need to be stabilized, since (for scalars) actual values are compared, not references.
  const legendVisible = series.length > 1 && size !== 'sparkline'
  const legendIsVertical = series.length > 3
  const hasStacking = plotOptions && hasPropertyWithValue(plotOptions, 'stacking', 'normal')
  const constructorType = showRangeSelector ? 'stockChart' : 'chart'

  // Stabilize array/object derived values
  const yAxisOptionsArray = useMemo(() => (Array.isArray(yAxisOptions) ? yAxisOptions : [yAxisOptions]), [yAxisOptions])
  const constructorFn = useMemo(() => (showRangeSelector ? Highstock : Highcharts), [showRangeSelector])

  const options: Options = useMemo(() => {
    const opts = merge(
      {},
      defaultOptions,
      {
        ...(legendIsVertical
          ? {
              accessibility: {
                keyboardNavigation: {
                  order: ['series', 'legend'],
                },
              },
            }
          : {}),
        chart: {
          type,
          height: typeof size === 'number' ? size : chartHeights[size],
        },
        time: {
          useUTC,
        },
        colors,
        exporting: {
          chartOptions: {
            title: {
              text: title,
            },
            caption: {
              text: description,
            },
          },
          filename: title,
        },
        lang: {
          accessibility: {
            chartContainerLabel: `${title}. Interactive chart.`,
            navigator: {
              groupLabel: `${title} Axis zoom`,
            },
          },
        },
        legend: {
          enabled: legendVisible,
          ...(legendIsVertical ? {align: 'right', layout: 'vertical', verticalAlign: 'middle'} : {}),
        },
        plotOptions: merge(
          {},
          defaultOptions.plotOptions,
          {
            series: {
              marker: {
                enabled: size !== 'sparkline',
              },
              enableMouseTracking: size !== 'sparkline',
            },
          },
          plotOptions,
        ),
        series,
        tooltip: merge(
          {},
          {
            enabled: size !== 'sparkline',
            shared: hasStacking,
          },
          tooltipOptions,
        ),
        xAxis: merge(
          {},
          {
            visible: size !== 'sparkline',
            gridLineWidth: size !== 'sparkline' ? 1 : 0,
            title: {
              text: size !== 'sparkline' ? xAxisTitle : undefined,
            },
          },
          xAxisOptions,
        ),
        yAxis: yAxisOptionsArray.map(yAxisConsumerOption => {
          if (!yAxisConsumerOption) return
          return merge(
            {},
            yAxisConfig,
            {
              visible: size !== 'sparkline',
              gridLineWidth: size !== 'sparkline' ? 1 : 0,
              title: {
                text: size !== 'sparkline' ? yAxisTitle : undefined,
              },
            },
            yAxisConsumerOption,
          )
        }),
        ...(showRangeSelector
          ? {rangeSelector: {enabled: true, inputEnabled: false, buttons: [], dropdown: 'never'}}
          : {}),
      },
      overrideOptionsNotRecommended,
    )

    // Include the navigator (the handles of rangeSelector) in the focus order
    if (showRangeSelector && opts.accessibility && opts.accessibility.keyboardNavigation) {
      opts.accessibility.keyboardNavigation.order = [
        ...(opts.accessibility?.keyboardNavigation?.order ?? []),
        'navigator',
      ]
    }

    // Apply a linear gradient fill to areaspline and area series
    if (opts.series && opts.colors) {
      let colorIndex = 0
      const colorfulSeries: typeof opts.series = []
      for (const singleSeries of opts.series) {
        if (singleSeries.type === 'areaspline' || singleSeries.type === 'area') {
          let color
          if (singleSeries.color) {
            color = singleSeries.color
          } else {
            color = opts.colors[colorIndex] as string
            colorIndex++
          }

          singleSeries.fillColor = {
            linearGradient: {x1: 0, x2: 0, y1: 0, y2: 1},
            stops: [
              [0, `color-mix(in srgb, ${color} 25%, transparent)`],
              [1, `color-mix(in srgb, ${color} 1%, transparent)`],
            ],
          }
          colorfulSeries.push(singleSeries)

          // After available colors run out, cycle through again
          if (colorIndex > opts.colors.length - 1) {
            colorIndex = 0
          }
        } else {
          colorfulSeries.push(singleSeries)
        }
      }
      opts.series = colorfulSeries
    }

    return opts
  }, [
    // Scalar dependencies
    type,
    xAxisTitle,
    yAxisTitle,
    useUTC,
    showRangeSelector,
    title,
    description,
    size,
    legendVisible,
    legendIsVertical,
    hasStacking,
    // Array/object dependencies
    colors,
    plotOptions,
    series,
    tooltipOptions,
    xAxisOptions,
    yAxisOptionsArray,
    overrideOptionsNotRecommended,
  ])

  return (
    <HighchartsReactOfficial
      constructorType={constructorType}
      highcharts={constructorFn}
      ref={chartRef}
      options={options}
    />
  )
}
Chart.displayName = 'ChartCard.Chart'
