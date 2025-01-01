import type {UseQueryResult} from '@github-ui/react-query'
import {screen} from '@testing-library/react'

import {render} from '../../../../test-utils/Render'
import {HistoricalAlertsFixedWithAutofixCard} from '../HistoricalAlertsFixedWithAutofixCard'
import useHistoricalAlertsFixedWithAutofixQuery from '../use-historical-alerts-fixed-with-autofix-query'

jest.mock('../use-historical-alerts-fixed-with-autofix-query')
function mockUseHistoricalAlertsFixedWithAutofixQuery<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(useHistoricalAlertsFixedWithAutofixQuery as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: true,
    data: [],
    ...result,
  })
}

describe('HistoricalAlertsFixedWithAutofixCard', () => {
  it('should render', async () => {
    mockUseHistoricalAlertsFixedWithAutofixQuery({
      isSuccess: true,
      data: {
        accepted: 1,
        suggested: 2,
      },
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
    }
    render(<HistoricalAlertsFixedWithAutofixCard {...props} />)
    expect(screen.getByText('Alerts fixed with autofix suggestions')).toBeInTheDocument()
  })

  it('should render loading state', () => {
    mockUseHistoricalAlertsFixedWithAutofixQuery({
      isPending: true,
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
    }
    render(<HistoricalAlertsFixedWithAutofixCard {...props} />)
    expect(screen.getByText('Alerts fixed with autofix suggestions')).toBeInTheDocument()
    expect(screen.getByTestId('data-card-loading-skeleton')).toBeInTheDocument()
  })

  it('should render error state', () => {
    mockUseHistoricalAlertsFixedWithAutofixQuery({
      isError: true,
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
    }
    render(<HistoricalAlertsFixedWithAutofixCard {...props} />)
    expect(screen.getByText('Alerts fixed with autofix suggestions')).toBeInTheDocument()
    expect(screen.getByText('Data could not be loaded right now')).toBeInTheDocument()
  })
})
