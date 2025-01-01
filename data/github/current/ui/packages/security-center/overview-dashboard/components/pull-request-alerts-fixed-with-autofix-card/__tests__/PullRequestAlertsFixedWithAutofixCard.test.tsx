import type {UseQueryResult} from '@github-ui/react-query'
import {screen} from '@testing-library/react'

import {render} from '../../../../test-utils/Render'
import PullRequestAlertsFixedWithAutofixCard from '../PullRequestAlertsFixedWithAutofixCard'
import usePullRequestAlertsFixedWithAutofixQuery from '../use-pull-request-alerts-fixed-with-autofix-query'

jest.mock('../use-pull-request-alerts-fixed-with-autofix-query')
function mockUsePullRequestAlertsFixedWithAutofixQuery<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(usePullRequestAlertsFixedWithAutofixQuery as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: true,
    data: [],
    ...result,
  })
}

describe('PullRequestAlertsFixedWithAutofixCard', () => {
  it('should render', async () => {
    mockUsePullRequestAlertsFixedWithAutofixQuery({
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
    render(<PullRequestAlertsFixedWithAutofixCard {...props} />)
    expect(screen.getByText('CodeQL pull request alerts fixed with autofix suggestions')).toBeInTheDocument()
  })

  it('should render loading state', () => {
    mockUsePullRequestAlertsFixedWithAutofixQuery({
      isPending: true,
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
    }
    render(<PullRequestAlertsFixedWithAutofixCard {...props} />)
    expect(screen.getByText('CodeQL pull request alerts fixed with autofix suggestions')).toBeInTheDocument()
    expect(screen.getByTestId('data-card-loading-skeleton')).toBeInTheDocument()
  })

  it('should render error state', () => {
    mockUsePullRequestAlertsFixedWithAutofixQuery({
      isError: true,
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
    }
    render(<PullRequestAlertsFixedWithAutofixCard {...props} />)
    expect(screen.getByText('CodeQL pull request alerts fixed with autofix suggestions')).toBeInTheDocument()
    expect(screen.getByText('Data could not be loaded right now')).toBeInTheDocument()
  })
})
