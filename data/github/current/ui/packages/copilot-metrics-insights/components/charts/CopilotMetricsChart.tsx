import {
  CopilotMetricsDataType,
  type AdoptionMetricsDateBucket,
  type AverageContributionDateBucket,
  type AveragePullRequestLeadTimeDateBucket,
  type CodeAcceptanceRateDateBucket,
  type CopilotHistoricalMetrics,
} from '../../types/copilot-metrics'
import {ChartCard} from '@github-ui/chart-card'
import styles from './CopilotMetricsChart.module.css'
import {clsx} from 'clsx'
import {
  chartColors,
  chartTitle,
  getAdoptionSeries,
  getAverageContributionSeries,
  getEngagementSeries,
  getPlotOptions,
  getTooltipOptions,
  getXAxisOptions,
  getYAxisOptions,
  seriesOrSinglePoint,
} from './CopilotMetricsChartHelper'

export interface CopilotMetricsChartProps {
  historicalMetrics: CopilotHistoricalMetrics
  metricsDataType: CopilotMetricsDataType
}

function CopilotMetricsChart({historicalMetrics, metricsDataType}: CopilotMetricsChartProps) {
  const metricsToSeries = () => {
    switch (metricsDataType) {
      case CopilotMetricsDataType.Adoption: {
        const {activeSeries, inactiveSeries, dormantSeries} = getAdoptionSeries(
          historicalMetrics.data as AdoptionMetricsDateBucket[],
        )
        return [
          {
            name: 'Active',
            data: seriesOrSinglePoint(activeSeries),
            type: 'areaspline',
            color: 'var(--data-blue-color-emphasis, var(--data-blue-color))',
            marker: {symbol: 'triangle'},
          },
          {
            name: 'Inactive',
            data: seriesOrSinglePoint(inactiveSeries),
            dashStyle: 'ShortDash',
            type: 'areaspline',
            color: 'var(--data-orange-color-emphasis, var(--data-orange-color))',
            marker: {symbol: 'circle'},
          },
          {
            name: 'Dormant',
            data: seriesOrSinglePoint(dormantSeries),
            dashStyle: 'Dash',
            type: 'areaspline',
            color: 'var(--data-gray-color-emphasis, var(--data-gray-color))',
            marker: {symbol: 'square'},
          },
        ]
      }
      case CopilotMetricsDataType.CodeAcceptance: {
        const {lowEngagementSeries, moderateEngagementSeries, highEngagementSeries} = getEngagementSeries(
          historicalMetrics.data as CodeAcceptanceRateDateBucket[],
        )
        return [
          {
            name: 'High engagement',
            data: seriesOrSinglePoint(highEngagementSeries),
            type: 'spline',
            color: 'var(--data-purple-color-emphasis, var(--data-purple-color))',
            marker: {symbol: 'triangle'},
          },
          {
            name: 'Moderate engagement',
            data: seriesOrSinglePoint(moderateEngagementSeries),
            type: 'spline',
            dashStyle: 'Dash',
            color: 'var(--data-blue-color-emphasis, var(--data-blue-color))',
            marker: {symbol: 'diamond'},
          },
          {
            name: 'Low engagement',
            data: seriesOrSinglePoint(lowEngagementSeries),
            type: 'spline',
            dashStyle: 'ShortDash',
            color: 'var(--data-teal-color-emphasis, var(--data-teal-color))',
            marker: {symbol: 'circle'},
          },
        ]
      }
      case CopilotMetricsDataType.AverageContribution: {
        const {noCopilotSeries, lowEngagementSeries, moderateEngagementSeries, highEngagementSeries} =
          getAverageContributionSeries(historicalMetrics.data as AverageContributionDateBucket[])
        return [
          {
            name: 'High Copilot engagement',
            data: seriesOrSinglePoint(highEngagementSeries),
            type: 'spline',
            color: 'var(--data-purple-color-emphasis, var(--data-purple-color))',
            marker: {symbol: 'triangle'},
          },
          {
            name: 'Moderate Copilot engagement',
            data: seriesOrSinglePoint(moderateEngagementSeries),
            type: 'spline',
            dashStyle: 'Dash',
            color: 'var(--data-blue-color-emphasis, var(--data-blue-color))',
            marker: {symbol: 'diamond'},
          },
          {
            name: 'Low Copilot engagement',
            data: seriesOrSinglePoint(lowEngagementSeries),
            type: 'spline',
            dashStyle: 'ShortDash',
            color: 'var(--data-teal-color-emphasis, var(--data-teal-color))',
            marker: {symbol: 'circle'},
          },
          {
            name: 'No Copilot',
            data: seriesOrSinglePoint(noCopilotSeries),
            type: 'spline',
            dashStyle: 'DashDot',
            color: 'var(--data-gray-color-emphasis, var(--data-gray-color))',
            marker: {symbol: 'square'},
          },
        ]
      }
      case CopilotMetricsDataType.AveragePullRequestLeadTime: {
        const {noCopilotSeries, lowEngagementSeries, moderateEngagementSeries, highEngagementSeries} =
          getAverageContributionSeries(historicalMetrics.data as AveragePullRequestLeadTimeDateBucket[])
        return [
          {
            name: 'High Copilot engagement',
            data: seriesOrSinglePoint(highEngagementSeries),
            type: 'spline',
            color: 'var(--data-purple-color-emphasis, var(--data-purple-color))',
            marker: {symbol: 'triangle'},
          },
          {
            name: 'Moderate Copilot engagement',
            data: seriesOrSinglePoint(moderateEngagementSeries),
            type: 'spline',
            dashStyle: 'Dash',
            color: 'var(--data-blue-color-emphasis, var(--data-blue-color))',
            marker: {symbol: 'diamond'},
          },
          {
            name: 'Low Copilot engagement',
            data: seriesOrSinglePoint(lowEngagementSeries),
            type: 'spline',
            dashStyle: 'ShortDash',
            color: 'var(--data-teal-color-emphasis, var(--data-teal-color))',
            marker: {symbol: 'circle'},
          },
          {
            name: 'No Copilot',
            data: seriesOrSinglePoint(noCopilotSeries),
            type: 'spline',
            dashStyle: 'DashDot',
            color: 'var(--data-gray-color-emphasis, var(--data-gray-color))',
            marker: {symbol: 'square'},
          },
        ]
      }
      default:
        return []
    }
  }

  const isAreaChart = metricsDataType === CopilotMetricsDataType.Adoption
  const chartType = isAreaChart ? 'areaspline' : 'spline'

  return (
    <div className={clsx(styles.CopilotMetricsChart)} data-testid="copilot-metrics-chart">
      <ChartCard size="large" border padding="normal" visibleControls={false} className="width-full">
        <ChartCard.Title as="h2">
          {chartTitle(historicalMetrics.overallStartDate, historicalMetrics.overallEndDate)}
        </ChartCard.Title>
        <ChartCard.Chart
          xAxisTitle=""
          colors={chartColors(metricsDataType)}
          tooltipOptions={getTooltipOptions(historicalMetrics, metricsDataType)}
          series={metricsToSeries()}
          xAxisOptions={getXAxisOptions()}
          yAxisOptions={getYAxisOptions(metricsDataType)}
          plotOptions={getPlotOptions(metricsDataType)}
          type={chartType}
          overrideOptionsNotRecommended={{
            legend: {
              reversed: true,
              verticalAlign: 'top',
              align: 'left',
              layout: 'horizontal',
            },
          }}
        />
      </ChartCard>
    </div>
  )
}

export default CopilotMetricsChart
