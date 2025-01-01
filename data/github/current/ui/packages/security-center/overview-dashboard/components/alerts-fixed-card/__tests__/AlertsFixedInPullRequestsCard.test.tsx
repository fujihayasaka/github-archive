import type {UseQueryResult} from '@github-ui/react-query'
import {screen} from '@testing-library/react'

import {render} from '../../../../test-utils/Render'
import AlertsFixedInPullRequestsCard from '../AlertsFixedInPullRequestsCard'
import UseAlertsFixedInPullRequestsQuery from '../use-alerts-fixed-in-pull-requests-query'

jest.mock('../use-alerts-fixed-in-pull-requests-query')
function mockUseAlertsFixedInPullRequestsQuery<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(UseAlertsFixedInPullRequestsQuery as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: true,
    data: {},
    ...result,
  })
}

describe('AlertsFixedInPullRequestsCard', () => {
  it('should render', async () => {
    mockUseAlertsFixedInPullRequestsQuery({
      isSuccess: true,
      data: {
        count: 100,
        total: 200,
        percentage: 50,
      },
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
      customProperties: [],
    }
    render(<AlertsFixedInPullRequestsCard {...props} />)

    expect(screen.getByText('CodeQL alerts fixed in pull requests')).toBeInTheDocument()
    expect(screen.getByText(100)).toBeInTheDocument()
    expect(screen.getByText('of 200')).toBeInTheDocument()
  })

  it('should render loading state', () => {
    mockUseAlertsFixedInPullRequestsQuery({
      isPending: true,
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
      customProperties: [],
    }
    render(<AlertsFixedInPullRequestsCard {...props} />)

    expect(screen.getByText('CodeQL alerts fixed in pull requests')).toBeInTheDocument()
    expect(screen.getByTestId('data-card-loading-skeleton')).toBeInTheDocument()
  })

  it('should render error state', () => {
    mockUseAlertsFixedInPullRequestsQuery({
      isError: true,
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
      customProperties: [],
    }
    render(<AlertsFixedInPullRequestsCard {...props} />)

    expect(screen.getByText('CodeQL alerts fixed in pull requests')).toBeInTheDocument()
    expect(screen.getByText('Data could not be loaded right now')).toBeInTheDocument()
  })
})
