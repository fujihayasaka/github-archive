import {act, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {
  getCopilotMetricsInsightsRoutePayload,
  getCompletionsAcceptanceRateRoutePayload,
  getGeneratedCodeAcceptanceRateRoutePayload,
  getAverageContributionRoutePayload,
  getAveragePullRequestLeadTimeRoutePayload,
} from '../../test-utils/mock-data'
import type {
  AdoptionMetricsDateBucket,
  CodeAcceptanceRateDateBucket,
  AverageContributionDateBucket,
  AveragePullRequestLeadTimeDateBucket,
  CopilotMetricsDataType,
} from '../../types/copilot-metrics'
import CopilotMetricsInsights from '../../components/CopilotMetricsInsights'
import type {CopilotMetricsInsightsPayload} from '../../routes/CopilotMetricsInsightsViewer'

function renderFromPayload(routePayload: CopilotMetricsInsightsPayload) {
  return render(
    <CopilotMetricsInsights
      metricsDataType={routePayload.metricsDataType}
      historicalMetrics={routePayload.historicalMetrics}
    />,
  )
}

describe('CopilotMetricsInsights', () => {
  test('renders with chart and table', async () => {
    const routePayload = getCopilotMetricsInsightsRoutePayload()
    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      renderFromPayload(routePayload)
    })

    const chart = await screen.findByTestId('chart-card')
    expect(chart).toBeInTheDocument()
    const table = screen.getByTestId('copilot-metrics-table')
    expect(table).toBeInTheDocument()

    expect(table).toHaveTextContent('Week')
    expect(table).toHaveTextContent('Total')
    expect(table).toHaveTextContent('Dormant')
    expect(table).toHaveTextContent('Inactive')
    expect(table).toHaveTextContent('Active')

    for (const row of routePayload.historicalMetrics.data as AdoptionMetricsDateBucket[]) {
      expect(table).toHaveTextContent(row.label)
      expect(table).toHaveTextContent(`${row.total}`)
      expect(table).toHaveTextContent(`${row.dormant} (${Math.round((row.dormant / row.total) * 100)}%)`)
      expect(table).toHaveTextContent(`${row.inactive} (${Math.round((row.inactive / row.total) * 100)}%)`)
      expect(table).toHaveTextContent(`${row.active} (${Math.round((row.active / row.total) * 100)}%)`)
    }
  })

  test('renders with code completions acceptance rate data', async () => {
    const routePayload = getCompletionsAcceptanceRateRoutePayload()
    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      renderFromPayload(routePayload)
    })

    const table = screen.getByTestId('copilot-metrics-table')
    expect(table).toBeInTheDocument()

    expect(table).toHaveTextContent('Week')
    expect(table).toHaveTextContent('Low engagement')
    expect(table).toHaveTextContent('Moderate engagement')
    expect(table).toHaveTextContent('High engagement')

    for (const row of routePayload.historicalMetrics.data as CodeAcceptanceRateDateBucket[]) {
      expect(table).toHaveTextContent(row.label)
      expect(table).toHaveTextContent(`${row.lowEngagement.acceptanceRate * 100}%`)
      expect(table).toHaveTextContent(`${row.lowEngagement.accepted} of ${row.lowEngagement.total}`)
      expect(table).toHaveTextContent(`${row.moderateEngagement.acceptanceRate * 100}%`)
      expect(table).toHaveTextContent(`${row.moderateEngagement.accepted} of ${row.moderateEngagement.total}`)
      expect(table).toHaveTextContent(`${row.highEngagement.acceptanceRate * 100}%`)
      expect(table).toHaveTextContent(`${row.highEngagement.accepted} of ${row.highEngagement.total}`)
    }
  })

  test('renders with generated code acceptance rate data', async () => {
    const routePayload = getGeneratedCodeAcceptanceRateRoutePayload()
    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      renderFromPayload(routePayload)
    })

    const table = screen.getByTestId('copilot-metrics-table')
    expect(table).toBeInTheDocument()

    const rateChart = screen.getByTestId('copilot-metrics-chart')
    expect(rateChart).toBeInTheDocument()

    expect(table).toHaveTextContent('Week')
    expect(table).toHaveTextContent('Low engagement')
    expect(table).toHaveTextContent('Moderate engagement')
    expect(table).toHaveTextContent('High engagement')

    for (const row of routePayload.historicalMetrics.data as CodeAcceptanceRateDateBucket[]) {
      expect(table).toHaveTextContent(row.label)
      expect(table).toHaveTextContent(`${row.lowEngagement.acceptanceRate * 100}%`)
      expect(table).toHaveTextContent(`${row.lowEngagement.accepted} of ${row.lowEngagement.total}`)
      expect(table).toHaveTextContent(`${row.moderateEngagement.acceptanceRate * 100}%`)
      expect(table).toHaveTextContent(`${row.moderateEngagement.accepted} of ${row.moderateEngagement.total}`)
      expect(table).toHaveTextContent(`${row.highEngagement.acceptanceRate * 100}%`)
      expect(table).toHaveTextContent(`${row.highEngagement.accepted} of ${row.highEngagement.total}`)
    }
  })

  test('renders with average contribution data', async () => {
    const routePayload = getAverageContributionRoutePayload()
    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      renderFromPayload(routePayload)
    })

    const table = screen.getByTestId('copilot-metrics-table')
    expect(table).toBeInTheDocument()

    expect(table).toHaveTextContent('Week')
    expect(table).toHaveTextContent('No Copilot')
    expect(table).toHaveTextContent('Low engagement')
    expect(table).toHaveTextContent('Moderate engagement')
    expect(table).toHaveTextContent('High engagement')

    for (const row of routePayload.historicalMetrics.data as AverageContributionDateBucket[]) {
      expect(table).toHaveTextContent(row.label)
      expect(table).toHaveTextContent(`${row.noCopilot.average}`)
      expect(table).toHaveTextContent(`${Math.round(row.noCopilot.percentDifference * 100)}%`)
      expect(table).toHaveTextContent(`${row.lowEngagement.average}`)
      expect(table).toHaveTextContent(`${Math.round(row.lowEngagement.percentDifference * 100)}%`)
      expect(table).toHaveTextContent(`${row.moderateEngagement.average}`)
      expect(table).toHaveTextContent(`${Math.round(row.moderateEngagement.percentDifference * 100)}%`)
      expect(table).toHaveTextContent(`${row.highEngagement.average}`)
      expect(table).toHaveTextContent(`${Math.round(row.highEngagement.percentDifference * 100)}%`)
    }
  })

  test('renders with average pull request lead time data', async () => {
    const routePayload = getAveragePullRequestLeadTimeRoutePayload()
    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      renderFromPayload(routePayload)
    })

    const table = screen.getByTestId('copilot-metrics-table')
    expect(table).toBeInTheDocument()

    expect(table).toHaveTextContent('Week')
    expect(table).toHaveTextContent('No Copilot')
    expect(table).toHaveTextContent('Low engagement')
    expect(table).toHaveTextContent('Moderate engagement')
    expect(table).toHaveTextContent('High engagement')

    for (const row of routePayload.historicalMetrics.data as AveragePullRequestLeadTimeDateBucket[]) {
      expect(table).toHaveTextContent(row.label)
      expect(table).toHaveTextContent(`${row.noCopilot.average}`)
      expect(table).toHaveTextContent(`${row.lowEngagement.average}`)
      expect(table).toHaveTextContent(`${Math.round(Math.abs(row.lowEngagement.percentDifference) * 100)}%`)
      expect(table).toHaveTextContent(`${row.moderateEngagement.average}`)
      expect(table).toHaveTextContent(`${Math.round(Math.abs(row.moderateEngagement.percentDifference) * 100)}%`)
      expect(table).toHaveTextContent(`${row.highEngagement.average}`)
      expect(table).toHaveTextContent(`${Math.round(Math.abs(row.highEngagement.percentDifference) * 100)}%`)
    }
  })

  test('does not render table for unknown metrics data type', async () => {
    const routePayload = getCopilotMetricsInsightsRoutePayload({
      metricsDataType: 'unknown_type' as CopilotMetricsDataType,
    })
    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      renderFromPayload(routePayload)
    })

    // Chart should still be rendered
    const chart = await screen.findByTestId('chart-card')
    expect(chart).toBeInTheDocument()

    // Table should not be rendered for unknown metrics data type
    const table = screen.queryByTestId('copilot-metrics-table')
    expect(table).not.toBeInTheDocument()
  })
})
