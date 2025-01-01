import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {EnablementTrendChart, type EnablementTrendChartProps} from '../EnablementTrendChart'

describe('EnablementTrendChart', () => {
  it('renders the comopnent with data', () => {
    const props: EnablementTrendChartProps = {
      state: 'ready',
      description: '',
      datasets: [
        {
          label: 'Alerts',
          data: [
            {x: '2023-01-01', y: 60},
            {x: '2023-01-15', y: 70},
            {x: '2023-02-01', y: 80},
            {x: '2023-02-15', y: 80},
            {x: '2023-03-01', y: 80},
            {x: '2023-03-15', y: 85},
          ],
        },
        {
          label: 'Security updates',
          data: [
            {x: '2023-01-01', y: 45},
            {x: '2023-01-15', y: 50},
            {x: '2023-02-01', y: 45},
            {x: '2023-02-15', y: 50},
            {x: '2023-03-01', y: 55},
            {x: '2023-03-15', y: 60},
          ],
        },
      ],
      trendValue: 10,
    }
    render(<EnablementTrendChart {...props} />)
    expect(screen.getByTestId('chart-card')).toBeInTheDocument()
    expect(screen.getByTestId('trend-indicator-value')).toBeInTheDocument()
  })

  it('shows a loading spinner when state is loading', () => {
    const props: EnablementTrendChartProps = {
      state: 'loading',
      description: '',
      datasets: [],
      trendValue: 0,
    }
    render(<EnablementTrendChart {...props} />)
    expect(screen.getByTestId('loading-indicator')).toBeInTheDocument()
  })

  it('shows a warning when state is error', () => {
    const props: EnablementTrendChartProps = {
      state: 'error',
      description: '',
      datasets: [],
      trendValue: 0,
    }
    render(<EnablementTrendChart {...props} />)
    expect(screen.getByTestId('error')).toBeInTheDocument()
  })

  it('shows a notice when state is no-data', () => {
    const props: EnablementTrendChartProps = {
      state: 'no-data',
      description: '',
      datasets: [],
      trendValue: 0,
    }
    render(<EnablementTrendChart {...props} />)
    expect(screen.getByTestId('no-data')).toBeInTheDocument()
  })
})
