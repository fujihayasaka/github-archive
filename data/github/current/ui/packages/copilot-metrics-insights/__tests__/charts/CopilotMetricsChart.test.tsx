import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import CopilotMetricsChart from '../../components/charts/CopilotMetricsChart'
import {
  CopilotMetricsDataType,
  type AdoptionMetricsDateBucket,
  type AverageContributionDateBucket,
  type CodeAcceptanceRateDateBucket,
} from '../../types/copilot-metrics'

describe('with adoption data', () => {
  test('renders chart correctly', () => {
    const copilotMetrics = {
      data: [
        {
          id: '1',
          label: 'Week 1',
          shortLabel: 'W1',
          startDate: '2025-01-01',
          endDate: '2025-01-07',
          active: 10,
          inactive: 5,
          dormant: 2,
          total: 100,
        },
        {
          id: '2',
          label: 'Week 2',
          shortLabel: 'W2',
          startDate: '2025-01-08',
          endDate: '2025-01-14',
          active: 12,
          inactive: 6,
          dormant: 3,
          total: 100,
        },
      ] as AdoptionMetricsDateBucket[],
      overallStartDate: '2025-01-01',
      overallEndDate: '2025-03-01',
    }

    render(<CopilotMetricsChart historicalMetrics={copilotMetrics} metricsDataType={CopilotMetricsDataType.Adoption} />)

    expect(screen.getByTestId('copilot-metrics-chart')).toBeInTheDocument()
    expect(screen.getByText('Jan 01, 2025 - Mar 01, 2025 (weekly intervals)')).toBeInTheDocument()

    expect(screen.getByLabelText('Active, series 1 of 3 with 2 data points.')).toBeInTheDocument()
    expect(screen.getByLabelText('Inactive, series 2 of 3 with 2 data points.')).toBeInTheDocument()
    expect(screen.getByLabelText('Dormant, series 3 of 3 with 2 data points.')).toBeInTheDocument()
  })

  test('handles single data point correctly', () => {
    const copilotMetrics = {
      data: [
        {
          id: '1',
          label: 'Week 1',
          shortLabel: 'W1',
          startDate: '2025-01-01',
          endDate: '2025-01-07',
          active: 10,
          inactive: 5,
          dormant: 2,
          total: 100,
        },
      ] as AdoptionMetricsDateBucket[],
      overallStartDate: '2025-01-01',
      overallEndDate: '2025-03-01',
    }

    render(<CopilotMetricsChart historicalMetrics={copilotMetrics} metricsDataType={CopilotMetricsDataType.Adoption} />)

    expect(screen.getByLabelText('Active, series 1 of 3 with 1 data point.')).toBeInTheDocument()
    expect(screen.getByLabelText('Inactive, series 2 of 3 with 1 data point.')).toBeInTheDocument()
    expect(screen.getByLabelText('Dormant, series 3 of 3 with 1 data point.')).toBeInTheDocument()
  })
})

describe('with engagement data', () => {
  test('renders segmented rate chart correctly', () => {
    const copilotMetrics = {
      data: [
        {
          id: '1',
          label: 'Week 1',
          shortLabel: 'W1',
          startDate: '2025-01-01',
          endDate: '2025-01-07',
          lowEngagement: {
            total: 100,
            accepted: 30,
            acceptanceRate: 0.3,
          },
          moderateEngagement: {
            total: 100,
            accepted: 50,
            acceptanceRate: 0.5,
          },
          highEngagement: {
            total: 100,
            accepted: 80,
            acceptanceRate: 0.8,
          },
        },
        {
          id: '2',
          label: 'Week 2',
          shortLabel: 'W2',
          startDate: '2025-01-08',
          endDate: '2025-01-14',
          lowEngagement: {
            total: 100,
            accepted: 35,
            acceptanceRate: 0.35,
          },
          moderateEngagement: {
            total: 100,
            accepted: 55,
            acceptanceRate: 0.55,
          },
          highEngagement: {
            total: 100,
            accepted: 85,
            acceptanceRate: 0.85,
          },
        },
      ] as CodeAcceptanceRateDateBucket[],
      overallStartDate: '2025-01-01',
      overallEndDate: '2025-03-01',
    }

    render(
      <CopilotMetricsChart
        historicalMetrics={copilotMetrics}
        metricsDataType={CopilotMetricsDataType.CodeAcceptance}
      />,
    )

    expect(screen.getByTestId('copilot-metrics-chart')).toBeInTheDocument()
    const chartContainer = screen.getByRole('region', {name: /Jan 01, 2025 - Mar 01, 2025 \(weekly intervals\)/})
    expect(chartContainer).toBeInTheDocument()

    const chartDescription = screen.getByText('Line chart with 3 lines.')
    expect(chartDescription).toBeInTheDocument()
  })

  test('handles single data point correctly', () => {
    const copilotMetrics = {
      overallStartDate: '2025-01-01',
      overallEndDate: '2025-03-01',
      data: [
        {
          id: '1',
          label: 'Week 1',
          shortLabel: 'W1',
          startDate: '2025-01-01',
          endDate: '2025-01-07',
          lowEngagement: {
            total: 100,
            accepted: 30,
            acceptanceRate: 0.3,
          },
          moderateEngagement: {
            total: 100,
            accepted: 50,
            acceptanceRate: 0.5,
          },
          highEngagement: {
            total: 100,
            accepted: 80,
            acceptanceRate: 0.8,
          },
        },
      ] as CodeAcceptanceRateDateBucket[],
    }

    render(
      <CopilotMetricsChart
        historicalMetrics={copilotMetrics}
        metricsDataType={CopilotMetricsDataType.CodeAcceptance}
      />,
    )

    expect(screen.getByTestId('copilot-metrics-chart')).toBeInTheDocument()
    const chartContainer = screen.getByRole('region', {name: /Jan 01, 2025 - Mar 01, 2025 \(weekly intervals\)/})
    expect(chartContainer).toBeInTheDocument()

    const chartDescription = screen.getByText('Line chart with 3 lines.')
    expect(chartDescription).toBeInTheDocument()

    expect(
      screen.getByText(
        'The chart has 1 X axis displaying Time. Data ranges from 2025-01-01 00:00:00 to 2025-01-01 00:00:00.',
      ),
    ).toBeInTheDocument()
  })
})

describe('Average Contribution Data', () => {
  test('renders average contribution chart correctly', () => {
    const copilotMetrics = {
      data: [
        {
          id: '1',
          label: 'Week 1',
          shortLabel: 'W1',
          startDate: '2025-01-01',
          endDate: '2025-01-07',
          noCopilot: {
            average: 10,
            percentDifference: 0.1,
          },
          lowEngagement: {
            average: 20,
            percentDifference: 0.2,
          },
          moderateEngagement: {
            average: 30,
            percentDifference: 0.3,
          },
          highEngagement: {
            average: 40,
            percentDifference: 0.4,
          },
        },
        {
          id: '2',
          label: 'Week 2',
          shortLabel: 'W2',
          startDate: '2025-01-08',
          endDate: '2025-01-14',
          noCopilot: {
            average: 15,
            percentDifference: 0.15,
          },
          lowEngagement: {
            average: 25,
            percentDifference: 0.25,
          },
          moderateEngagement: {
            average: 35,
            percentDifference: 0.35,
          },
          highEngagement: {
            average: 45,
            percentDifference: 0.45,
          },
        },
      ] as AverageContributionDateBucket[],
      overallStartDate: '2025-01-01',
      overallEndDate: '2025-03-01',
    }

    render(
      <CopilotMetricsChart
        historicalMetrics={copilotMetrics}
        metricsDataType={CopilotMetricsDataType.AverageContribution}
      />,
    )

    expect(screen.getByTestId('copilot-metrics-chart')).toBeInTheDocument()
    const chartContainer = screen.getByRole('region', {name: /Jan 01, 2025 - Mar 01, 2025 \(weekly intervals\)/})
    expect(chartContainer).toBeInTheDocument()

    const chartDescription = screen.getByText('Line chart with 4 lines.')
    expect(chartDescription).toBeInTheDocument()
  })
})

test('handles single data point correctly', () => {
  const copilotMetrics = {
    overallStartDate: '2025-01-01',
    overallEndDate: '2025-03-01',
    data: [
      {
        id: '1',
        label: 'Week 1',
        shortLabel: 'W1',
        startDate: '2025-01-01',
        endDate: '2025-01-07',
        noCopilot: {
          average: 10,
          percentDifference: 0.1,
        },
        lowEngagement: {
          average: 20,
          percentDifference: 0.2,
        },
        moderateEngagement: {
          average: 30,
          percentDifference: 0.3,
        },
        highEngagement: {
          average: 40,
          percentDifference: 0.4,
        },
      },
    ] as AverageContributionDateBucket[],
  }

  render(
    <CopilotMetricsChart
      historicalMetrics={copilotMetrics}
      metricsDataType={CopilotMetricsDataType.AverageContribution}
    />,
  )

  expect(screen.getByTestId('copilot-metrics-chart')).toBeInTheDocument()
  const chartContainer = screen.getByRole('region', {name: /Jan 01, 2025 - Mar 01, 2025 \(weekly intervals\)/})
  expect(chartContainer).toBeInTheDocument()

  const chartDescription = screen.getByText('Line chart with 4 lines.')
  expect(chartDescription).toBeInTheDocument()

  expect(
    screen.getByText(
      'The chart has 1 X axis displaying Time. Data ranges from 2025-01-01 00:00:00 to 2025-01-01 00:00:00.',
    ),
  ).toBeInTheDocument()
})
