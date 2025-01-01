import {act, screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotMetricsInsights} from '../routes/CopilotMetricsInsights'
import {getCopilotMetricsInsightsRoutePayload} from '../test-utils/mock-data'

test('renders CopilotMetricsInsights with chart and table', async () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload()
  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(async () => {
    render(<CopilotMetricsInsights />, {
      routePayload,
    })
  })

  const heading = screen.getByText('Copilot user onboarding', {selector: 'h2'})
  expect(heading).toBeInTheDocument()

  const chart = await screen.findByTestId('chart-card')
  expect(chart).toBeInTheDocument()
  expect(screen.getByTestId('copilot-metrics-table')).toBeInTheDocument()
})

test('renders banner when payload CSV download error occurs', async () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload({
    csvDownloadUrl: 'https://example.com/download-error',
  })

  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(async () => {
    render(<CopilotMetricsInsights />, {
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
    copilotAdoptionMetrics: {
      ...getCopilotMetricsInsightsRoutePayload().copilotAdoptionMetrics,
      historicalAdoptionData: [],
    },
  })

  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(async () => {
    render(<CopilotMetricsInsights />, {
      routePayload,
    })
  })

  const blankslate = screen.getByTestId('copilot-metrics-blankslate')
  expect(blankslate).toBeInTheDocument()
  expect(within(blankslate).getByText('Welcome to Copilot user onboarding metrics')).toBeInTheDocument()

  expect(within(blankslate).getByRole('link')).toHaveAttribute('href', 'invite-members-link')
  expect(within(blankslate).getByRole('link')).toHaveTextContent('Invite members')
})
