import {getISOWeek} from 'date-fns/getISOWeek'
import {
  CopilotMetricsDataType,
  type AdoptionMetricsDateBucket,
  type AverageContributionDateBucket,
  type CodeAcceptanceRateDateBucket,
  type CopilotHistoricalMetrics,
} from '../../types/copilot-metrics'
import {fullDateRangeString, rollingDateRangeString} from '../../helpers/date'
import styles from './CopilotMetricsChart.module.css'
import {clsx} from 'clsx'
import {Heading} from '@primer/react'

export function seriesOrSinglePoint(data: Array<[number, number]> | undefined) {
  if (!data) return []

  if (data.length === 1) {
    const point = data[0]
    const x: number = point ? point[0] : 0
    const y: number = point ? point[1] : 0

    return [
      {
        x,
        y,
        marker: {
          enabled: true,
        },
      },
    ]
  }
  return data
}

export function chartTitle(overallStartDate: string, overallEndDate: string) {
  const dateRange = fullDateRangeString(overallStartDate, overallEndDate)
  return (
    <div className={clsx(styles.CopilotMetricsChartTitle)}>
      <Heading as="h2" className="f4">
        {dateRange} (weekly intervals)
      </Heading>
    </div>
  )
}

export function chartColors(metricsDataType: CopilotMetricsDataType) {
  switch (metricsDataType) {
    case CopilotMetricsDataType.Adoption:
      return [
        'var(--data-blue-color-emphasis, var(--data-blue-color))',
        'var(--data-orange-color-emphasis, var(--data-orange-color))',
        'var(--data-gray-color-emphasis, var(--data-gray-color))',
      ]
    case CopilotMetricsDataType.CodeAcceptance:
      return [
        'var(--data-purple-color-emphasis, var(--data-purple-color))',
        'var(--data-blue-color-emphasis, var(--data-blue-color))',
        'var(--data-teal-color-emphasis, var(--data-teal-color))',
      ]
    case CopilotMetricsDataType.AverageContribution:
      return [
        'var(--data-purple-color-emphasis, var(--data-purple-color))',
        'var(--data-blue-color-emphasis, var(--data-blue-color))',
        'var(--data-teal-color-emphasis, var(--data-teal-color))',
      ]
    default:
      // Just a placeholder for now before we add code for M2
      return [
        'var(--data-blue-color-emphasis, var(--data-blue-color))',
        'var(--data-orange-color-emphasis, var(--data-orange-color))',
        'var(--data-gray-color-emphasis, var(--data-gray-color))',
      ]
  }
}

export function getAdoptionSeries(data: AdoptionMetricsDateBucket[]) {
  const activeSeries: Array<[number, number]> = []
  const inactiveSeries: Array<[number, number]> = []
  const dormantSeries: Array<[number, number]> = []

  for (const bucket of data) {
    const startDate = new Date(bucket.startDate).getTime()

    activeSeries.push([startDate, bucket.active])
    inactiveSeries.push([startDate, bucket.inactive])
    dormantSeries.push([startDate, bucket.dormant])
  }

  return {activeSeries, inactiveSeries, dormantSeries}
}

export function getEngagementSeries(data: CodeAcceptanceRateDateBucket[]) {
  const lowEngagementSeries: Array<[number, number]> = []
  const moderateEngagementSeries: Array<[number, number]> = []
  const highEngagementSeries: Array<[number, number]> = []

  for (const bucket of data) {
    const startDate = new Date(bucket.startDate).getTime()

    lowEngagementSeries.push([startDate, bucket.lowEngagement.acceptanceRate * 100])
    moderateEngagementSeries.push([startDate, bucket.moderateEngagement.acceptanceRate * 100])
    highEngagementSeries.push([startDate, bucket.highEngagement.acceptanceRate * 100])
  }

  return {lowEngagementSeries, moderateEngagementSeries, highEngagementSeries}
}

export function getAverageContributionSeries(data: AverageContributionDateBucket[]) {
  const noCopilotSeries: Array<[number, number]> = []
  const lowEngagementSeries: Array<[number, number]> = []
  const moderateEngagementSeries: Array<[number, number]> = []
  const highEngagementSeries: Array<[number, number]> = []

  for (const bucket of data) {
    const startDate = new Date(bucket.startDate).getTime()

    noCopilotSeries.push([startDate, bucket.noCopilot.average])
    lowEngagementSeries.push([startDate, bucket.lowEngagement.average])
    moderateEngagementSeries.push([startDate, bucket.moderateEngagement.average])
    highEngagementSeries.push([startDate, bucket.highEngagement.average])
  }

  return {noCopilotSeries, lowEngagementSeries, moderateEngagementSeries, highEngagementSeries}
}

export function getTooltipOptions(
  historicalMetrics: CopilotHistoricalMetrics,
  metricsDataType: CopilotMetricsDataType,
) {
  return {
    shared: true,
    useHTML: true,
    formatter(this: Highcharts.TooltipFormatterContextObject) {
      if (this.points) {
        let tooltipBody = ''
        const dataPoint = historicalMetrics.data[this.point.index]
        if (!dataPoint) return ''
        const hourSuffix = metricsDataType === CopilotMetricsDataType.AveragePullRequestLeadTime ? 'h' : ''

        const tooltipDate = rollingDateRangeString(dataPoint.startDate, dataPoint.endDate)
        // eslint-disable-next-line github/unescaped-html-literal
        const tooltipHeader = `<div class=${styles.CopilotMetricsChartTooltipHeader}>${tooltipDate}</div><br/>`
        const tooltipData = this.points.map(point => {
          return `
            <div class="${styles.CopilotMetricsChartTooltipDataPoint}">
              <div>
                <span style="color:${point.color}; padding-right: 4px">\u25CF</span>
                <span style="padding-right: 4px">${point.series.name}</span>
              </div>
              <span><b>${point.y}${hourSuffix}</b></span>
            </div>
          `
        })

        tooltipBody += tooltipHeader
        // eslint-disable-next-line github/unescaped-html-literal
        tooltipBody += `<div>${tooltipData.join('<br/>')}</div>`

        if (metricsDataType === CopilotMetricsDataType.Adoption) {
          tooltipBody += `
            <br/>
            <div class="${styles.CopilotMetricsChartTooltipDataPoint}">
              <div style="margin-left: 14px">Total</div>
              <span><b>${(dataPoint as AdoptionMetricsDateBucket).total}</b></span>
            </div>
          `
        }

        // eslint-disable-next-line github/unescaped-html-literal
        return `<div>${tooltipBody}</div>`
      }
    },
  }
}

export function getXAxisOptions(): Highcharts.XAxisOptions {
  return {
    type: 'datetime',
    gridLineDashStyle: 'Dash',
    labels: {
      formatter(this: Highcharts.AxisLabelsFormatterContextObject) {
        const date = new Date(this.value)
        let weekNumber = getISOWeek(date) + 1

        // If week number is 53, reset it to 1
        if (weekNumber === 53) weekNumber = 1

        return `W${weekNumber}`
      },
    },
  }
}

export function getYAxisOptions(metricsDataType: CopilotMetricsDataType): Highcharts.YAxisOptions {
  return {
    gridLineDashStyle: 'Dash',
    ...(metricsDataType === CopilotMetricsDataType.CodeAcceptance && {
      min: 0,
      max: 100,
      labels: {
        format: '{value}%',
      },
    }),
    ...(metricsDataType === CopilotMetricsDataType.AveragePullRequestLeadTime && {
      labels: {
        format: '{value}h',
      },
    }),
  }
}

export function getPlotOptions(metricsDataType: CopilotMetricsDataType): Highcharts.PlotOptions {
  return {
    series: {
      marker: {
        enabled: false,
        states: {
          hover: {
            enabled: true,
          },
        },
      },
      stacking: metricsDataType === CopilotMetricsDataType.Adoption && 'normal',
    },
  }
}
