import type {UseQueryResult} from '@tanstack/react-query'
import {screen} from '@testing-library/react'

import {calculatePreviousDateRange} from '../../../../common/utils/date-period'
import {render} from '../../../../test-utils/Render'
import {ReopenedAlertsCard} from '../ReopenedAlertsCard'
import {getTrend, useReopenedAlertsQuery} from '../use-reopened-alerts-query'

afterEach(() => {
  jest.clearAllMocks()
  jest.resetAllMocks()
})

jest.mock('../use-reopened-alerts-query')
function mockUseReopenedAlertsQuery(): void {
  ;(useReopenedAlertsQuery as jest.Mock)
    .mockReturnValueOnce({
      count: 100,
      isSuccess: true,
      isPending: false,
      isError: false,
    })
    .mockReturnValueOnce({
      count: 200,
      isSuccess: true,
      isPending: false,
      isError: false,
    })
}
function mockUseReopenedAlertsQueryNonSuccess<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(useReopenedAlertsQuery as jest.Mock).mockReturnValue({
    isSuccess: false,
    ...result,
  })
}
function mockGetTrend(): void {
  ;(getTrend as jest.Mock).mockReturnValue(50)
}

describe('ReopenedAlertsCard', () => {
  const query = 'archived: false'
  const startDate = '2023-01-01'
  const endDate = '2023-01-31'
  const previousDateRange = calculatePreviousDateRange(startDate, endDate)

  it('renders the component with the correct props', () => {
    mockUseReopenedAlertsQuery()

    render(<ReopenedAlertsCard query={query} startDate={startDate} endDate={endDate} />)

    expect(useReopenedAlertsQuery).toHaveBeenCalled()
    expect(useReopenedAlertsQuery).toHaveBeenCalledWith({query, startDate, endDate})
    expect(useReopenedAlertsQuery).toHaveBeenCalledWith({
      query,
      startDate: previousDateRange.startDate,
      endDate: previousDateRange.endDate,
    })

    expect(screen.getByText('Reopened alerts')).toBeInTheDocument()
  })

  it('fetches and displays the correct data', async () => {
    mockUseReopenedAlertsQuery()
    mockGetTrend()

    render(<ReopenedAlertsCard query={query} startDate={startDate} endDate={endDate} />)

    expect(useReopenedAlertsQuery).toHaveBeenCalled()
    expect(useReopenedAlertsQuery).toHaveBeenCalledWith({query, startDate, endDate})
    expect(useReopenedAlertsQuery).toHaveBeenCalledWith({
      query,
      startDate: previousDateRange.startDate,
      endDate: previousDateRange.endDate,
    })

    expect(screen.getByText('100')).toBeInTheDocument()
    expect(screen.getByText('50%')).toBeInTheDocument()
  })

  it('displays a spinner if loading is true', async () => {
    mockUseReopenedAlertsQueryNonSuccess({
      isPending: true,
    })

    render(<ReopenedAlertsCard query={query} startDate={startDate} endDate={endDate} />)

    expect(screen.queryByText(/%/)).not.toBeInTheDocument()
    expect(screen.getByTestId('data-card-loading-skeleton')).toBeInTheDocument()
  })
})
