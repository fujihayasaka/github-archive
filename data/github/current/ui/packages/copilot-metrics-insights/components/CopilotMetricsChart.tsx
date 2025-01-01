import type {CopilotAdoptionMetrics} from '../types/copilot-metrics'
import {ChartCard} from '@github-ui/chart-card'
import styles from './CopilotMetricsChart.module.css'
import {getISOWeek} from 'date-fns'
import {clsx} from 'clsx'
import {fullDateRangeString, rollingDateRangeString} from '../helpers/date'
import {InfoIcon} from '@primer/octicons-react'
import {AnchoredOverlay, Heading, IconButton, Link} from '@primer/react'
import {useState} from 'react'

interface CopilotMetricsChartProps {
  copilotMetrics: CopilotAdoptionMetrics
}

function CopilotMetricsChart({copilotMetrics}: CopilotMetricsChartProps) {
  const chartTitle = (metrics: CopilotAdoptionMetrics) => {
    const dateRange = fullDateRangeString(metrics.overallStartDate, metrics.overallEndDate)
    return (
      <div className={clsx(styles.CopilotMetricsChartTitle)}>
        <Heading as="h2" className="f4">
          {dateRange} (weekly intervals)
        </Heading>
        <ChartInfoDialog />
      </div>
    )
  }

  const metricsToSeries = (metrics: CopilotAdoptionMetrics) => {
    const adoptionData = metrics.historicalAdoptionData
    const activeSeries: Array<[number, number]> = []
    const inactiveSeries: Array<[number, number]> = []
    const notOnboardedSeries: Array<[number, number]> = []

    for (const bucket of adoptionData) {
      const startDate = new Date(bucket.startDate).getTime()

      activeSeries.push([startDate, bucket.active])
      inactiveSeries.push([startDate, bucket.inactive])
      notOnboardedSeries.push([startDate, bucket.notOnboarded])
    }

    return {
      activeSeries,
      inactiveSeries,
      notOnboardedSeries,
    }
  }
  const {activeSeries, inactiveSeries, notOnboardedSeries} = metricsToSeries(copilotMetrics)

  const seriesOrSinglePoint = (data: Array<[number, number]>) => {
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

  return (
    <div className={clsx(styles.CopilotMetricsChart)} data-testid="copilot-metrics-chart">
      <ChartCard size="large" border padding="normal" visibleControls={false} className="width-full">
        <ChartCard.Title as="h2">{chartTitle(copilotMetrics)}</ChartCard.Title>
        <ChartCard.Chart
          xAxisTitle=""
          colors={['var(--fgColor-accent)', 'var(--fgColor-danger)', 'var(--fgColor-attention)']}
          tooltipOptions={{
            shared: true,
            useHTML: true,
            formatter() {
              if (this.points) {
                let tooltipBody = ''
                const dataPoint = copilotMetrics.historicalAdoptionData[this.point.index]
                if (!dataPoint) return ''

                const tooltipDate = rollingDateRangeString(dataPoint.startDate, dataPoint.endDate)
                // eslint-disable-next-line github/unescaped-html-literal
                const tooltipHeader = `<div class=${styles.CopilotMetricsChartTooltipHeader}>${tooltipDate}</div><br/>`
                const tooltipData = this.points.map(point => {
                  return `
                    <div class="${styles.CopilotMetricsChartTooltipDataPoint}">
                      <div><span style="color:${point.color}; padding-right: 4px">\u25CF</span>${point.series.name}</div>
                      <span><b>${point.y}</b></span>
                    </div>
                  `
                })

                tooltipBody += tooltipHeader
                // eslint-disable-next-line github/unescaped-html-literal
                tooltipBody += `<div>${tooltipData.join('<br/>')}</div><br/>`

                tooltipBody += `
                  <div class="${styles.CopilotMetricsChartTooltipDataPoint}">
                    <div style="margin-left: 14px">Total</div>
                    <span><b>${dataPoint.total}</b></span>
                  </div>
                `

                // eslint-disable-next-line github/unescaped-html-literal
                return `<div class="${styles.CopilotMetricsChartTooltip}">${tooltipBody}</div>`
              }
            },
          }}
          series={[
            {
              name: 'Active',
              data: seriesOrSinglePoint(activeSeries),
              type: 'areaspline',
              marker: {
                symbol: 'triangle',
              },
            },
            {
              name: 'Inactive',
              data: seriesOrSinglePoint(inactiveSeries),
              dashStyle: 'ShortDash',
              type: 'areaspline',
              marker: {
                symbol: 'circle',
              },
            },
            {
              name: 'Not onboarded',
              data: seriesOrSinglePoint(notOnboardedSeries),
              dashStyle: 'Dash',
              type: 'areaspline',
              marker: {
                symbol: 'square',
              },
            },
          ]}
          xAxisOptions={{
            type: 'datetime',
            gridLineDashStyle: 'Dash',
            labels: {
              formatter() {
                const date = new Date(this.value)
                let weekNumber = getISOWeek(date) + 1

                // If week number is 53, reset it to 1
                if (weekNumber === 53) weekNumber = 1

                return `W${weekNumber}`
              },
            },
          }}
          yAxisOptions={{
            gridLineDashStyle: 'Dash',
          }}
          plotOptions={{
            series: {
              marker: {
                enabled: false,
                states: {
                  hover: {
                    enabled: true,
                  },
                },
              },
            },
          }}
          type={'area'}
        />
      </ChartCard>
    </div>
  )
}

const ChartInfoDialog = () => {
  const [open, setOpen] = useState(false)
  const chartInfoDialogLink = '#'

  return (
    <AnchoredOverlay
      open={open}
      onOpen={() => setOpen(true)}
      onClose={() => setOpen(false)}
      align="center"
      renderAnchor={anchorProps => {
        return (
          // eslint-disable-next-line primer-react/a11y-remove-disable-tooltip
          <IconButton
            {...anchorProps}
            icon={InfoIcon}
            variant="invisible"
            aria-label="More information"
            aria-labelledby={undefined}
            unsafeDisableTooltip
            data-testid="copilot-metrics-chart-info-button"
          />
        )
      }}
      overlayProps={{
        sx: {width: 240, height: 260},
      }}
    >
      <div className={clsx(styles.CopilotMetricsChartInfoDialog)}>
        <Heading as="h4" className={clsx(styles.CopilotMetricsChartInfoDialogHeader)}>
          Copilot user onboarding
        </Heading>
        <p className={styles.CopilotMetricsChartInfoDialogText}>
          Copilot onboarding trends help evaluate and fine-tune license assignments, making sure organization members
          are actively using their Copilot seats.
        </p>
        <Link href={chartInfoDialogLink}>Learn more about Copilot onboarding metrics</Link>
      </div>
    </AnchoredOverlay>
  )
}

export default CopilotMetricsChart
