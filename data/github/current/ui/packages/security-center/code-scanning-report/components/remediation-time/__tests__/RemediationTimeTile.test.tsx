import type {UseQueryResult} from '@github-ui/react-query'
import {screen} from '@testing-library/react'

import {render} from '../../../../test-utils/Render'
import RemediationTimeTile from '../RemediationTimeTile'
import useRemediationTimeQuery from '../use-remediation-time-query'

jest.mock('../use-remediation-time-query')
function mockUseRemediationTimeQuery<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(useRemediationTimeQuery as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: true,
    data: [],
    ...result,
  })
}

describe('RemediationTimeTile', () => {
  it('should render', () => {
    mockUseRemediationTimeQuery({
      isSuccess: true,
      data: {
        remediationTimeInHoursWithAutofixSuggested: 25.2,
        remediationTimeInHoursWithNoAutofixSuggested: 30.1,
      },
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
    }
    render(<RemediationTimeTile {...props} />)
    expect(screen.getByText('Mean time to remediate')).toBeInTheDocument()
    expect(screen.getByTestId('chart-card')).toBeInTheDocument()
  })

  it('should render loading state', () => {
    mockUseRemediationTimeQuery({
      isPending: true,
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
    }
    render(<RemediationTimeTile {...props} />)
    expect(screen.getByText('Mean time to remediate')).toBeInTheDocument()
    expect(screen.getByTestId('loading-indicator')).toBeInTheDocument()
  })

  it('should render error state', () => {
    mockUseRemediationTimeQuery({
      isError: true,
    })

    const props = {
      query: '',
      startDate: '2024-01-01',
      endDate: '2024-12-31',
    }
    render(<RemediationTimeTile {...props} />)
    expect(screen.getByText('Mean time to remediate')).toBeInTheDocument()
    expect(screen.getByTestId('error')).toBeInTheDocument()
  })
})
