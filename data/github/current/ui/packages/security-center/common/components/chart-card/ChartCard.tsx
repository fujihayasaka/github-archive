import {ChartCard as PrimerChartCard} from '@github-ui/chart-card'
import DataCard from '@github-ui/data-card'
import {AlertIcon, ShieldCheckIcon} from '@primer/octicons-react'
import {Spinner} from '@primer/react'
import {Blankslate, useSlots} from '@primer/react/experimental'
import type {Chart, Point, SeriesOptionsType, Tooltip, TooltipFormatterContextObject} from 'highcharts'
import {useCallback, useEffect, useMemo, useState} from 'react'

export type ChartHeight = number | 'auto'
export type ChartWidth = number | '100%'
export type ChartSize = 'large' | 'medium' | 'small'
export type ChartType = 'area' | 'column' | 'bar' | 'line' | 'areaspline'

type ChartCardBlankslate = {
  isLoading: boolean
  message?: string
  isError?: boolean
  ariaLabel?: string
}

type ChartCardProps = {
  blankslate?: ChartCardBlankslate
  height?: ChartHeight
  width?: ChartWidth
  size: ChartSize
  title: string
  type: ChartType
  series: SeriesOptionsType[]
  xAxisTitle: string
  xAxisMin?: number | undefined
  xAxisMax?: number | undefined
  yAxisTitle: string
  yAxisMin?: number | undefined
  tickInterval?: number | undefined
  pointRange?: number | undefined
  pointStart?: number | undefined
  pointPlacement?: 'on' | 'between' | undefined
  categories?: string[]
  children?: React.ReactNode
  isPercentage?: boolean
  displayYAxisTitle?: boolean
  showDataLabels?: boolean
  showTooltipTotalCount?: boolean
  showNamedPointTooltipsOnly?: boolean
  hideTitle?: boolean
  hideLegend?: boolean
  hideTooltip?: boolean
  categoryTotals?: Record<string, number>
  chartMarginRight?: number | undefined
  xAxisLabelFormatter?: (labelText: string, total: number, isFirst: boolean) => string
}

/******************************************************************************
 * This component wraps Primer's ChartCard component and adds feature specific
 * highcharts customizations based on the type of chart.
 *
 * Common design pattern should live in Primer's ChartCard component instead.
 ******************************************************************************/
const DEFAULT_CATEGORY_TOTALS: Record<string, number> = {}
function ChartCard({
  blankslate,
  height = 'auto',
  width = '100%',
  size,
  title,
  type,
  series,
  xAxisTitle,
  xAxisMin = undefined,
  xAxisMax = undefined,
  yAxisTitle,
  yAxisMin = undefined,
  tickInterval = undefined,
  pointRange = undefined,
  pointStart = undefined,
  pointPlacement = undefined,
  categories,
  children,
  isPercentage = false,
  displayYAxisTitle = false,
  showDataLabels = false,
  showTooltipTotalCount = false,
  showNamedPointTooltipsOnly = false,
  hideTitle = false,
  hideLegend = false,
  hideTooltip = false,
  categoryTotals = DEFAULT_CATEGORY_TOTALS,
  chartMarginRight = undefined,
  xAxisLabelFormatter = undefined,
}: ChartCardProps): JSX.Element {
  const [slots] = useSlots(children, {
    description: PrimerChartCard.Description,
    actions: PrimerChartCard.TrailingVisual,
  })
  const [cardHeight, setCardHeight] = useState<ChartHeight>(height)

  useEffect(() => {
    // Forces auto on height on tiny screens to prevent overflowing chart content
    const recalculatedHeight = screen.width <= 320 ? 'auto' : height
    setCardHeight(recalculatedHeight)
  }, [setCardHeight, height])

  const chartTestId = useMemo(() => {
    const formattedTitle = title ? title.toLowerCase().replace(/\s+/g, '-') : ''
    return `${type}-chart-card:${formattedTitle}`
  }, [title, type])

  const xAxisOptions = useMemo(() => {
    const options = {
      title: {
        text: null,
      },
    } as Highcharts.XAxisOptions

    if (categories) {
      options.categories = categories || []
      if (type === 'areaspline') {
        // Dependabot metrics page uses areaspline chart type
        // with categories.
        if (tickInterval) {
          options.tickInterval = tickInterval
        }
        options.tickmarkPlacement = 'on'
        options.maxPadding = 0
        options.startOnTick = false
        options.endOnTick = false
        options.labels = {
          align: 'left',
          useHTML: true,
          formatter(): string {
            const labelText = String(this.value)
            const count = categoryTotals?.[labelText] ?? 0
            return xAxisLabelFormatter ? String(xAxisLabelFormatter(labelText, count, this.isFirst)) : labelText
          },
        }
      }
    } else {
      options.type = 'datetime'
      options.labels = {
        format: '{value:%b %e}', // Month and day
      }
      options.gridLineDashStyle = 'ShortDash'

      // Forces the x-axis to show labels only when there is data instead of
      // showing labels based on the available space.
      // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
      const seriesDataSample: number[][] | undefined = series[0]?.data
      options.tickPositions = seriesDataSample?.map(i => i[0] || 0) || []
    }

    if (xAxisMin !== undefined) options.min = xAxisMin
    if (xAxisMax !== undefined) options.max = xAxisMax

    return options
  }, [categories, xAxisMin, xAxisMax, type, categoryTotals, tickInterval, xAxisLabelFormatter, series])

  const yAxisOptions = useMemo(() => {
    const options = {
      title: {
        text: null,
      },
      labels: {
        formatter: amount => {
          let value = amount.value
          if (typeof amount.value === 'number') {
            value = Math.abs(amount.value)
          }
          return value.toLocaleString()
        },
      },
      stackLabels: {
        enabled: showDataLabels,
      },
      gridLineDashStyle: 'ShortDash',
      min: yAxisMin,
    } as Highcharts.YAxisOptions

    if (isPercentage) {
      options.min = 0
      options.max = 100
      options.title = undefined
      options.stackLabels!.format = '{total}%'
    }

    if (displayYAxisTitle) {
      options.title = undefined
    }

    return options
  }, [showDataLabels, isPercentage, yAxisMin, displayYAxisTitle])

  const chartPointFormatter = useCallback(
    function (this: Point) {
      const legend = this.series.legendItem?.line || this.series.legendItem?.symbol
      const legendHtml = legend?.element?.outerHTML || '●'

      const valueString = `${Math.abs(this.y || 0).toLocaleString()}${isPercentage ? '%' : ''}`
      return (
        // eslint-disable-next-line github/unescaped-html-literal
        `<tr>
          <td class="pt-1">
            <div class="d-flex flex-items-center">
              <svg class="mr-1" width="16" height="16">
                <g transform="translate(0,-4)">${legendHtml}</g>
              </svg>${this.series.name}
            </div>
          </td>
          <td  class="pt-1 pl-3 v-align-bottom text-right">
            <strong>${valueString}</strong>
          </td>
        </tr>`
      )
    },
    [isPercentage],
  )

  const chartTooltipWithTotalCountFormatter = useCallback(
    function (this: TooltipFormatterContextObject, tooltip: Tooltip) {
      const out = tooltip.defaultFormatter.call(this, tooltip)
      if (showNamedPointTooltipsOnly && !this.point.name) {
        return false
      }
      if (Array.isArray(out)) {
        const totalCount = this.points?.reduce((sum, point) => sum + (point?.y || 0), 0) || 0
        // eslint-disable-next-line github/unescaped-html-literal
        const total = `<tr>
          <td class="pt-2">Total</td>
          <td class="pt-2 text-right">
            <strong>${totalCount.toLocaleString()}</strong>
          </td>
        </tr>`
        out.splice(out.length - 1, 0, total)
        return out
      } else {
        return out
      }
    },
    [showNamedPointTooltipsOnly],
  )

  const tooltipOptions = useMemo(() => {
    if (hideTooltip) {
      return {enabled: false} as Highcharts.TooltipOptions
    }

    const options = {
      shared: true, // Data points with the same xaxis value are shown in the same tooltip
      pointFormatter: chartPointFormatter, // Required to match line style in tooltip
    } as Highcharts.TooltipOptions

    if (type === 'area' || showTooltipTotalCount) {
      // Required to shows a total count in the tooltip
      options.formatter = chartTooltipWithTotalCountFormatter
    }

    if (type === 'column' || type === 'bar') {
      // Keep tooltip away from data point to avoid overlapping with
      // the column bar.
      options.distance = 45
    }

    return options
  }, [type, hideTooltip, showTooltipTotalCount, chartPointFormatter, chartTooltipWithTotalCountFormatter])

  const plotOptions = useMemo(() => {
    const options = {
      series: {
        marker: {
          enabled: false, // Hide marker on data points until hovered
        },
      },
    } as Highcharts.PlotOptions

    if (type === 'area' || type === 'column' || type === 'bar' || type === 'areaspline') {
      options.series.stacking = 'normal'
    }
    if (pointRange) {
      options.series.pointRange = pointRange
    }
    if (pointStart) {
      options.series.pointStart = pointStart
    }
    if (pointPlacement) {
      options.series.pointPlacement = pointPlacement
    }
    return options
  }, [pointPlacement, pointRange, pointStart, type])

  const onChartRender = useCallback(function (this: Chart) {
    for (const chartSeries of this.series) {
      // Required redraw override to show border on legend item
      if (chartSeries.type === 'column') {
        const legendItemElement = chartSeries.legendItem?.symbol?.element
        if (legendItemElement !== undefined) {
          const borderColor = chartSeries.userOptions.borderColor as string
          legendItemElement.setAttribute('stroke', borderColor)
          legendItemElement.setAttribute('stroke-width', '2')
        }
      }
    }
  }, [])

  const chartOptions = useMemo(() => {
    const pointValueSuffix = isPercentage ? '%' : undefined

    return {
      // Force keyboard navigation order regardless the number of legend items
      // Context: https://github.com/github/accessibility/issues/7491
      accessibility: {
        keyboardNavigation: {
          order: ['legend', 'series'],
        },
        point: {
          valueSuffix: pointValueSuffix,
        },
      },
      // Force legend to be horizontal regardless the number of legend items
      // ChartCard shows legend items on the right when there are more than 3 items
      legend: {
        enabled: !hideLegend,
        verticalAlign: 'top',
        align: 'left',
        layout: 'horizontal',
      },
      chart: {
        events: {
          render: onChartRender,
        },
        ...(chartMarginRight !== undefined && {marginRight: chartMarginRight}),
      },
      tooltip: {
        // render the tooltip in an absolutely positioned <div> instead
        // of SVG so it always floats above all axes / series.
        outside: true,
      },
    } as Highcharts.Options
  }, [isPercentage, onChartRender, hideLegend, chartMarginRight])

  function renderBody(): JSX.Element {
    if (blankslate === undefined) {
      return (
        <PrimerChartCard size={size} border={false} padding="none" visibleControls={false}>
          {slots.description && <PrimerChartCard.Description>{slots.description}</PrimerChartCard.Description>}
          <PrimerChartCard.Chart
            type={type}
            series={series}
            xAxisTitle={xAxisTitle}
            xAxisOptions={xAxisOptions}
            yAxisTitle={yAxisTitle}
            yAxisOptions={yAxisOptions}
            tooltipOptions={tooltipOptions}
            plotOptions={plotOptions}
            overrideOptionsNotRecommended={chartOptions}
          />
        </PrimerChartCard>
      )
    }

    if (blankslate.isLoading) {
      return (
        <div
          data-testid="loading-indicator"
          className="bgColor-muted height-full d-flex flex-items-center flex-justify-center flex-1 rounded-2 mb-2"
        >
          <Spinner />
        </div>
      )
    }

    return (
      <div
        data-testid={blankslate.isError ? 'error' : 'no-data'}
        className="d-flex flex-column flex-justify-center height-full"
        role="region"
        aria-label={blankslate.ariaLabel}
      >
        <Blankslate>
          <Blankslate.Visual>
            {blankslate.isError ? <AlertIcon size="medium" /> : <ShieldCheckIcon size="medium" />}
          </Blankslate.Visual>
          <Blankslate.Description>{blankslate.message}</Blankslate.Description>
        </Blankslate>
      </div>
    )
  }

  return (
    <DataCard
      data-testid={chartTestId}
      cardTitle={hideTitle ? undefined : title}
      action={slots.actions}
      as="h3"
      sx={{
        height: cardHeight,
        width,
        display: 'flex',
        flexDirection: 'column',
        paddingTop: '16px',
        paddingBottom: '16px',
      }}
    >
      {renderBody()}
    </DataCard>
  )
}

ChartCard.Description = PrimerChartCard.Description
ChartCard.Actions = PrimerChartCard.TrailingVisual

export default ChartCard
