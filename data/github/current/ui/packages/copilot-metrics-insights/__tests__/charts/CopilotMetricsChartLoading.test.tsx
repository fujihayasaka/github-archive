import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotMetricsChartLoading} from '../../components/charts/CopilotMetricsChartLoading'

test('CopilotMetricsChartLoading is same height as Chart', async () => {
  render(<CopilotMetricsChartLoading title="loading" />)

  const loading = screen.getByTestId('copilot-metrics-chart-loading')
  expect(loading).toHaveClass('CopilotMetricsChart')
})

test('CopilotMetricsChartLoading shows loading state after delay', async () => {
  render(<CopilotMetricsChartLoading title="loading" delay={5} />)

  expect(screen.getByTestId('copilot-metrics-chart-loading')).toBeInTheDocument()
  expect(screen.queryByTestId('copilot-metrics-chart-loading-title')).not.toBeInTheDocument()
  const title = await screen.findByTestId('copilot-metrics-chart-loading-title')
  expect(title).toBeInTheDocument()
  expect(title).toHaveTextContent('loading')
})
