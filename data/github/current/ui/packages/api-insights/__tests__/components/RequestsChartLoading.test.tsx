import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {RequestsChartLoading} from '../../components/RequestsChartLoading'

test('RequestsChartLoading is same height as Chart', async () => {
  render(<RequestsChartLoading title="loading" />)

  const loading = screen.getByTestId('requests-chart-loading')
  expect(loading).toHaveClass('requestsChart')
})

test('RequestsChartLoading shows loading state after delay', async () => {
  render(<RequestsChartLoading title="loading" delay={5} />)

  expect(screen.getByTestId('requests-chart-loading')).toBeInTheDocument()
  expect(screen.queryByTestId('requests-chart-loading-title')).not.toBeInTheDocument()
  const title = await screen.findByTestId('requests-chart-loading-title')
  expect(title).toBeInTheDocument()
  expect(title).toHaveTextContent('loading')
})
