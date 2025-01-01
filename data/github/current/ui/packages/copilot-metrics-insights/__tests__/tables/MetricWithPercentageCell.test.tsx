import {render, screen} from '@testing-library/react'
import {MetricWithPercentageCell} from '../../components/tables/MetricWithPercentageCell'

describe('MetricWithPercentageCell', () => {
  it('renders the metric and percentage correctly', () => {
    render(<MetricWithPercentageCell metric={25} total={100} />)

    expect(screen.getByText('25 (25%)')).toBeInTheDocument()
  })

  it('handles zero total gracefully', () => {
    render(<MetricWithPercentageCell metric={0} total={0} />)

    expect(screen.getByText('0')).toBeInTheDocument()
    expect(screen.queryByText('%')).not.toBeInTheDocument()
  })
})
