import {screen, act} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {expect, it} from '@github-ui/tests'
import {StafftoolsCopilotMetricsDashboards} from '../StafftoolsCopilotMetricsDashboards'
import {getStafftoolsCopilotMetricsDashboardsProps} from './utils/mock-data'

it('Renders the StafftoolsCopilotMetricsDashboards with dashboard chart and table', async () => {
  const props = getStafftoolsCopilotMetricsDashboardsProps()
  // eslint-disable-next-line testing-library/no-unnecessary-act
  await act(async () => {
    render(<StafftoolsCopilotMetricsDashboards {...props} />)
  })

  expect(screen.getByText('Dashboard Title')).toBeInTheDocument()
  const chart = await screen.findByTestId('chart-card', undefined, {
    timeout: 10000,
  })
  expect(chart).toBeInTheDocument()
  const table = screen.getByTestId('copilot-metrics-table')
  expect(table).toBeInTheDocument()
})
