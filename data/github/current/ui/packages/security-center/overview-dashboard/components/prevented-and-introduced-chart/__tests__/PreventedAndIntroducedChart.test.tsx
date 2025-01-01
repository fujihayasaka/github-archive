import type {UseQueryResult} from '@tanstack/react-query'
import {screen} from '@testing-library/react'

import {render} from '../../../../test-utils/Render'
import {PreventedAndIntroducedChart} from '../PreventedAndIntroducedChart'
import {getTotalAlertCountData, usePreventedAndIntroducedChartData} from '../use-prevented-and-introduced-chart-data'

jest.mock('../use-prevented-and-introduced-chart-data')
function mockUsePreventedAndIntroducedChartData<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(usePreventedAndIntroducedChartData as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: true,
    data: [],
    ...result,
  })
}
function mockUseTotalAlertCountData(count: number): void {
  ;(getTotalAlertCountData as jest.Mock).mockReturnValue(count || 0)
}

describe('PreventedAndIntroducedChart', () => {
  const props = {
    query: 'archived:false',
    startDate: '2022-01-01',
    endDate: '2023-01-31',
  }

  it('renders the loading spinner', () => {
    mockUsePreventedAndIntroducedChartData({
      isPending: true,
    })
    mockUseTotalAlertCountData(5)

    render(<PreventedAndIntroducedChart {...props} />)

    expect(screen.getByText('Prevented vs. Introduced')).toBeInTheDocument()
    expect(screen.getByTestId('loading-indicator')).toBeInTheDocument()
  })

  it('should render', async () => {
    mockUsePreventedAndIntroducedChartData({
      isSuccess: true,
      data: [
        {label: 'Introduced', data: [{x: '2024-01-01', y: 1}]},
        {label: 'Prevented', data: [{x: '2024-01-01', y: 2}]},
      ],
    })
    mockUseTotalAlertCountData(5)

    render(<PreventedAndIntroducedChart {...props} />)

    expect(screen.getByText('Prevented vs. Introduced')).toBeInTheDocument()
    expect(screen.getByTestId('chart-card')).toBeInTheDocument()
  })

  it('displays a error state', async () => {
    mockUsePreventedAndIntroducedChartData({
      isError: true,
    })
    mockUseTotalAlertCountData(5)

    render(<PreventedAndIntroducedChart {...props} />)

    expect(screen.getByText('Prevented vs. Introduced')).toBeInTheDocument()
    expect(await screen.findByTestId('error')).toBeInTheDocument()
  })

  it('displays a no data state when no data is returned', async () => {
    mockUsePreventedAndIntroducedChartData({
      data: [],
    })
    mockUseTotalAlertCountData(0)

    render(<PreventedAndIntroducedChart {...props} />)

    expect(screen.getByText('Prevented vs. Introduced')).toBeInTheDocument()
    expect(await screen.findByTestId('no-data')).toBeInTheDocument()
  })

  it('displays a no data state when total count of alerts is 0', async () => {
    mockUsePreventedAndIntroducedChartData({
      isSuccess: true,
      data: [
        {label: 'Introduced', data: [{x: '2024-01-01', y: 0}]},
        {label: 'Prevented', data: [{x: '2024-01-01', y: 0}]},
      ],
    })
    mockUseTotalAlertCountData(0)

    render(<PreventedAndIntroducedChart {...props} />)

    expect(screen.getByText('Prevented vs. Introduced')).toBeInTheDocument()
    expect(await screen.findByTestId('no-data')).toBeInTheDocument()
  })
})
