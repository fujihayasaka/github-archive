import {render, screen} from '@testing-library/react'
import {RateCell} from '../../components/tables/RateCell'
import type {AcceptanceCounts} from '../../types/copilot-metrics'

describe('RateCell', () => {
  const mockCounts: AcceptanceCounts = {
    total: 4000,
    accepted: 3000,
    acceptanceRate: 0.75,
  }

  it('renders the acceptance rate as a percentage', () => {
    render(<RateCell counts={mockCounts} unit="items" />)

    expect(screen.getByText('75%')).toBeInTheDocument()
  })

  it('renders the accepted and total counts with the unit', () => {
    render(<RateCell counts={mockCounts} unit="items" />)

    expect(screen.getByText('3,000 of 4,000 items')).toBeInTheDocument()
  })
})
