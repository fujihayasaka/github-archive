import {act, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import CopilotMetricsChart from '../components/CopilotMetricsChart'

test('renders chart correctly', () => {
  const copilotMetrics = {
    historicalAdoptionData: [
      {
        id: '1',
        label: 'Week 1',
        shortLabel: 'W1',
        startDate: '2025-01-01',
        endDate: '2025-01-07',
        active: 10,
        inactive: 5,
        notOnboarded: 2,
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
        notOnboarded: 3,
        total: 100,
      },
    ],
    overallStartDate: '2025-01-01',
    overallEndDate: '2025-03-01',
  }

  render(<CopilotMetricsChart copilotMetrics={copilotMetrics} />)

  expect(screen.getByTestId('copilot-metrics-chart')).toBeInTheDocument()
  expect(screen.getByText('Jan 01, 2025 - Mar 01, 2025 (weekly intervals)')).toBeInTheDocument()

  expect(screen.getByLabelText('Active, series 1 of 3 with 2 data points.')).toBeInTheDocument()
  expect(screen.getByLabelText('Inactive, series 2 of 3 with 2 data points.')).toBeInTheDocument()
  expect(screen.getByLabelText('Not onboarded, series 3 of 3 with 2 data points.')).toBeInTheDocument()
})

test('handles single data point correctly', () => {
  const copilotMetrics = {
    historicalAdoptionData: [
      {
        id: '1',
        label: 'Week 1',
        shortLabel: 'W1',
        startDate: '2025-01-01',
        endDate: '2025-01-07',
        active: 10,
        inactive: 5,
        notOnboarded: 2,
        total: 100,
      },
    ],
    overallStartDate: '2025-01-01',
    overallEndDate: '2025-03-01',
  }

  render(<CopilotMetricsChart copilotMetrics={copilotMetrics} />)

  expect(screen.getByLabelText('Active, series 1 of 3 with 1 data point.')).toBeInTheDocument()
  expect(screen.getByLabelText('Inactive, series 2 of 3 with 1 data point.')).toBeInTheDocument()
  expect(screen.getByLabelText('Not onboarded, series 3 of 3 with 1 data point.')).toBeInTheDocument()
})

test('handles info button click', async () => {
  const copilotMetrics = {
    historicalAdoptionData: [
      {
        id: '1',
        label: 'Week 1',
        shortLabel: 'W1',
        startDate: '2025-01-01',
        endDate: '2025-01-07',
        active: 10,
        inactive: 5,
        notOnboarded: 2,
        total: 100,
      },
    ],
    overallStartDate: '2025-01-01',
    overallEndDate: '2025-03-01',
  }

  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(() => {
    render(<CopilotMetricsChart copilotMetrics={copilotMetrics} />)
  })

  const infoButton = screen.getByTestId('copilot-metrics-chart-info-button')
  act(() => {
    infoButton.click()
  })

  expect(screen.getByText('Copilot user onboarding')).toBeInTheDocument()
  expect(
    screen.getByText(
      'Copilot onboarding trends help evaluate and fine-tune license assignments, making sure organization members are actively using their Copilot seats.',
    ),
  ).toBeInTheDocument()
  expect(screen.getByRole('link').getAttribute('href')).toBe('#')
})
