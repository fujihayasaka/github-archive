import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import CopilotMetricsTable from '../components/CopilotMetricsTable'
import {getCopilotMetricsInsightsRoutePayload} from '../test-utils/mock-data'

const setDate = '2024-01-10T12:00:00Z'
beforeAll(() => {
  jest.useFakeTimers().setSystemTime(new Date(setDate))
})

afterAll(() => {
  jest.useRealTimers()
})

test('should render the CopilotMetricsTable', () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload()
  render(<CopilotMetricsTable copilotMetrics={routePayload.copilotAdoptionMetrics} />)

  expect(screen.getByTestId('copilot-metrics-table')).toBeInTheDocument()

  const headers = ['Week', 'Total', 'Not onboarded', 'Inactive', 'Active']
  for (const headerText of headers) {
    const header = screen.getByText(headerText)
    expect(header).toBeInTheDocument()
  }

  const firstRow = screen.getByRole('row', {name: /Week 52/})
  expect(firstRow).toBeInTheDocument()
})

test('should display the correct data in table cells', () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload()
  render(<CopilotMetricsTable copilotMetrics={routePayload.copilotAdoptionMetrics} />)

  const week52Row = screen.getByRole('row', {name: /Week 52/})

  expect(week52Row).toHaveTextContent('100')
  expect(week52Row).toHaveTextContent('10 (10%)')
  expect(week52Row).toHaveTextContent('80 (80%)')
})

test('should have correct accessibility attributes', () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload()
  render(<CopilotMetricsTable copilotMetrics={routePayload.copilotAdoptionMetrics} />)

  const table = screen.getByRole('table')
  expect(table).toHaveAttribute('role', 'table')
  expect(table).toHaveAttribute('aria-describedby', 'copilot-metrics-subtitle')
  expect(table).toHaveAttribute('aria-labelledby', 'copilot-metrics')

  const headers = screen.getAllByRole('columnheader')
  expect(headers.length).toBe(5)
  for (const header of headers) {
    expect(header).toHaveAttribute('scope', 'col')
  }
})

test('should render weekCell with two different years', () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload()
  render(<CopilotMetricsTable copilotMetrics={routePayload.copilotAdoptionMetrics} />)

  const weekCell = screen.getByText('Dec 29, 2022 - Jan 04, 2023')
  expect(weekCell).toBeInTheDocument()
  expect(screen.queryByText('Dec 29 - Jan 04, 2023')).not.toBeInTheDocument()
})

test('should render weekCell with same year', () => {
  const routePayload = getCopilotMetricsInsightsRoutePayload()

  render(<CopilotMetricsTable copilotMetrics={routePayload.copilotAdoptionMetrics} />)

  expect(screen.getByText('Jan 05 - Jan 11, 2023')).toBeInTheDocument()
  expect(screen.queryByText('Jan 05, 2023 - Jan 11, 2023')).not.toBeInTheDocument()
})
