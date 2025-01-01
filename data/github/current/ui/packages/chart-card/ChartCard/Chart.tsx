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
import {applyHighchartsOverrides} from './highcharts-overrides'
import {toYYYYMMDD} from './toYYYYMMDD'

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

// Apply overrides
applyHighchartsOverrides()

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
  colors?: Array<string | Highcharts.GradientColorObject>
  overrideOptionsNotRecommended?: Highcharts.Options
  plotOptions?: Highcharts.PlotOptions
  series: Highcharts.SeriesOptionsType[]
  type: string
  xAxisTitle?: string
  xAxisOptions?: Highcharts.XAxisOptions
  yAxisTitle?: string
  yAxisOptions?: Highcharts.YAxisOptions | Highcharts.YAxisOptions[]
  tooltipOptions?: Highcharts.TooltipOptions
  useUTC?: boolean
  showRangeSelector?: boolean
  dataGrouping?: boolean
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

const Chart = ({
  // Scalar props
  type = 'line',
  xAxisTitle,
  yAxisTitle,
  useUTC = true,
  showRangeSelector = false,
  dataGrouping = false,
  // Array/object props
  colors: _colors,
  plotOptions: _plotOptions,
  series: _series,
  xAxisOptions: _xAxisOptions,
  yAxisOptions: _yAxisOptions,
  tooltipOptions: _tooltipOptions,
  overrideOptionsNotRecommended: _overrideOptionsNotRecommended,
}: ChartProps) => {
  // Get context
  const {title, size, chartRef} = useContext(ChartCardContext)

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
  // make this a prop
  const constructorType = showRangeSelector || dataGrouping ? 'stockChart' : 'chart'

  // Stabilize array/object derived values
  const yAxisOptionsArray = useMemo(() => (Array.isArray(yAxisOptions) ? yAxisOptions : [yAxisOptions]), [yAxisOptions])
  const constructorFn = useMemo(() => (constructorType === 'stockChart' ? Highstock : Highcharts), [constructorType])

  const options: Options = useMemo(() => {
    const opts = merge(
      {},
      defaultOptions,
      {
        accessibility: {
          ...(legendIsVertical
            ? {
                keyboardNavigation: {
                  order: ['series', 'legend'],
                },
              }
            : {}),
          ...(title
            ? {
                screenReaderSection: {
                  // avoid rendering extra heading
                  // eslint-disable-next-line github/unescaped-html-literal
                  beforeChartFormat: `<div>{typeDescription}</div><div>{chartSubtitle}</div><div>{chartLongdesc}</div><div>{playAsSoundButton}</div><div>{viewTableButton}</div><div>{xAxisDescription}</div><div>{yAxisDescription}</div><div>{annotationsTitle}{annotationsList}</div>`,
                },
              }
            : {}),
        },
        chart: {
          type,
          height: typeof size === 'number' ? size : chartHeights[size],
          events: {
            render() {
              if (showRangeSelector) {
                // This setTimeout makes the code run _after_ the range selector’s handles (and their proxy elements) have been rendered.
                window.setTimeout(() => {
                  // Get the range selector’s left and right handles’ proxies
                  const [leftHandle, rightHandle] = Array.from(
                    chartRef.current?.container.current?.querySelectorAll(
                      '.highcharts-a11y-proxy-group-navigator input[type=range]',
                    ) || [],
                  )
                  // Get the min and max x-axis values (both ‘currently shown’ and ‘possible to show’)
                  // These type casts are necessary because 'dataMin' and 'dataMax' are only available on the xAxis object when the rangeSelector is enabled.
                  const {dataMin, dataMax, min, max} =
                    ((this as unknown as Highcharts.Chart).xAxis?.[0] as unknown as {
                      dataMin: number
                      dataMax: number
                    } & Pick<Highcharts.Chart['xAxis'][0], 'min' | 'max'>) || {}
                  // Update the handles’ proxies’ `aria-valuemin`, `aria-valuemax`, `aria-valuenow`, and `aria-valuetext` attributes so screen readers announce the current and possible ranges
                  if (
                    leftHandle &&
                    rightHandle &&
                    dataMin !== undefined &&
                    dataMax !== undefined &&
                    min !== undefined &&
                    max !== undefined
                  ) {
                    leftHandle.setAttribute('aria-label', 'Start of selected range')
                    leftHandle.setAttribute('aria-valuemin', dataMin.toString())
                    leftHandle.setAttribute('aria-valuemax', dataMax.toString())
                    leftHandle.setAttribute('aria-valuenow', min.toString())

                    rightHandle.setAttribute('aria-label', 'End of selected range')
                    rightHandle.setAttribute('aria-valuemin', dataMin.toString())
                    rightHandle.setAttribute('aria-valuemax', dataMax.toString())
                    rightHandle.setAttribute('aria-valuenow', max.toString())
                  }
                  const readableMin = toYYYYMMDD(min)
                  const readableMax = toYYYYMMDD(max)
                  if (leftHandle && rightHandle && readableMin && readableMax) {
                    leftHandle.setAttribute('aria-valuetext', readableMin)
                    rightHandle.setAttribute('aria-valuetext', readableMax)
                  }
                }, 0)
              }
            },
          },
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
          },
          filename: title,
          csv: {
            dateFormat: '%Y-%m-%d',
          },
        },
        lang: {
          accessibility: {
            chartContainerLabel: title ? `${title}. Interactive chart.` : 'Interactive chart.',
            navigator: {
              groupLabel: `${title} Axis zoom`,
            },
          },
        },
        legend: {
          enabled: legendVisible,
          symbolRadius: type === 'column' || type === 'bar' ? 0 : undefined,
          ...(legendIsVertical ? {align: 'right', layout: 'vertical', verticalAlign: 'middle'} : {}),
        },
        plotOptions: merge(
          {},
          defaultOptions.plotOptions,
          {
            series: {
              marker: {
                enabled: size !== 'sparkline' && type !== 'spline',
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

          singleSeries.fillColor ||= {
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
    size,
    legendVisible,
    legendIsVertical,
    hasStacking,
    // Array/object dependencies
    chartRef,
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
// Chart.displayName = 'ChartCard.Chart'

export default Chart
