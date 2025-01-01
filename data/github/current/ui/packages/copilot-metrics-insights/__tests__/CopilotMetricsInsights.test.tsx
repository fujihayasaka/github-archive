import {act, screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotMetricsInsightsViewer} from '../routes/CopilotMetricsInsightsViewer'
import {getCopilotMetricsInsightsRoutePayload} from '../test-utils/mock-data'
import type {AdoptionMetricsDateBucket} from '../types/copilot-metrics'

test('renders CopilotMetricsInsightsViewer with chart and table', async () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload()
  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(async () => {
    render(<CopilotMetricsInsightsViewer />, {
      routePayload,
    })
  })

  const heading = screen.getByText('Copilot user onboarding', {selector: 'h2'})
  expect(heading).toBeInTheDocument()

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

test('renders banner when payload CSV download error occurs', async () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload({
    csvDownloadUrl: 'https://example.com/download-error',
    showCopilotMetricsCatalog: false,
  })

  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(async () => {
    render(<CopilotMetricsInsightsViewer />, {
      routePayload,
    })
  })

  const downloadButton = screen.getByRole('button', {name: 'Download CSV'})
  act(() => {
    downloadButton.click()
  })

  const banner = screen.getByText('An error occurred while exporting the CSV.')
  expect(banner).toBeInTheDocument()
})

test('renders blankslate component when no data is available', async () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload({
    historicalMetrics: {
      ...getCopilotMetricsInsightsRoutePayload().historicalMetrics,
      data: [],
    },
  })

  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(async () => {
    render(<CopilotMetricsInsightsViewer />, {
      routePayload,
    })
  })

  const blankslate = screen.getByTestId('copilot-metrics-blankslate')
  expect(blankslate).toBeInTheDocument()
  expect(within(blankslate).getByText('Welcome to Copilot user onboarding metrics')).toBeInTheDocument()

  expect(within(blankslate).getByRole('link')).toHaveAttribute('href', 'copilot-seat-management-link')
  expect(within(blankslate).getByRole('link')).toHaveTextContent('Invite members')
})

test('renders blankslate component when less than 2 weeks of data', async () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload({
    historicalMetrics: {
      ...getCopilotMetricsInsightsRoutePayload().historicalMetrics,
      data: [
        {
          id: '1',
          label: 'Week 1',
          shortLabel: 'W1',
          startDate: '2023-01-01',
          endDate: '2023-01-07',
          total: 4,
          active: 2,
          inactive: 1,
          dormant: 1,
        },
      ],
    },
  })
  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(async () => {
    render(<CopilotMetricsInsightsViewer />, {
      routePayload,
    })
  })
  const blankslate = screen.getByTestId('copilot-metrics-members-required-blankslate')
  expect(blankslate).toBeInTheDocument()
  expect(within(blankslate).getByText('Welcome to Copilot user onboarding metrics')).toBeInTheDocument()
  expect(within(blankslate).getByRole('link')).toHaveAttribute('href', 'invite-members-link')
  expect(within(blankslate).getByRole('link')).toHaveTextContent('Invite members')
})
