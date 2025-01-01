import {render, screen} from '@testing-library/react'
import {WeekCell} from '../../components/tables/WeekCell'
import type {BaseDateBucket} from '../../types/copilot-metrics'

describe('WeekCell', () => {
  const mockRow: BaseDateBucket = {
    id: '1',
    label: 'Week 1',
    shortLabel: 'W1',
    startDate: '2025-03-31',
    endDate: '2025-04-06',
  }

  it('renders the week label correctly', () => {
    render(<WeekCell row={mockRow} />)

    expect(screen.getByText('Week 1')).toBeInTheDocument()
  })

  it('renders the rolling date range string', () => {
    render(<WeekCell row={mockRow} />)

    expect(screen.getByText('Mar 31 - Apr 06, 2025')).toBeInTheDocument()
  })

  it('correctly renders the date when spanning across years', () => {
    render(
      <WeekCell
        row={{
          id: '1',
          label: 'Week 1',
          shortLabel: 'W1',
          startDate: '2024-12-30',
          endDate: '2025-01-05',
        }}
      />,
    )

    expect(screen.getByText('Dec 30, 2024 - Jan 05, 2025')).toBeInTheDocument()
  })
})
