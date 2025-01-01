import type {UseQueryResult} from '@github-ui/react-query'
import {screen} from '@testing-library/react'

import {render} from '../../../../test-utils/Render'
import {AlertTrendsChart} from '../AlertTrendsChart'
import {calculatePreviousTwoDays} from '../calculate-previous-two-days'
import {useAlertTrendsQuery} from '../use-alert-trends-query'

afterEach(() => {
  jest.clearAllMocks()
})

jest.mock('../calculate-previous-two-days')
const mockCalculatePreviousTwoDays = jest
  .mocked(calculatePreviousTwoDays)
  .mockReturnValue({startDate: '2023-01-01', endDate: '2023-01-02'})

jest.mock('../use-alert-trends-query', () => ({
  ...jest.requireActual('../use-alert-trends-query'),
  useAlertTrendsQuery: jest.fn(),
}))

function mockUseAlertTrendsQuery<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  jest.mocked(useAlertTrendsQuery).mockReturnValue(
    // Mock response from 3 parallel fetches within useQueries()
    new Array(3).fill({
      isSuccess: true,
      isPending: false,
      isError: false,
      data: {alertTrends: {}},
      ...result,
    }),
  )
}

describe('AlertTrendsChart', () => {
  const query = 'archived:false'
  const startDate = '2023-01-03'
  const endDate = '2023-01-31'

  it('should render chart with open state', () => {
    mockUseAlertTrendsQuery({
      data: {
        alertTrends: {
          // eslint-disable-next-line @typescript-eslint/naming-convention
          Low: [{x: '2024-01-10', y: 1}],
          // eslint-disable-next-line @typescript-eslint/naming-convention
          Medium: [{x: '2024-01-10', y: 2}],
          // eslint-disable-next-line @typescript-eslint/naming-convention
          High: [{x: '2024-01-10', y: 3}],
          // eslint-disable-next-line @typescript-eslint/naming-convention
          Critical: [{x: '2024-01-10', y: 4}],
        },
      },
    })

    render(
      <AlertTrendsChart query={query} startDate={startDate} endDate={endDate} isOpenSelected grouping="severity" />,
    )

    expect(screen.getByText('Open alerts over time')).toBeInTheDocument()
    expect(screen.getByTestId('chart-card')).toBeInTheDocument()
    expect(screen.getByTestId('grouping-selector')).toBeInTheDocument()
  })

  it('should render chart with closed state', () => {
    mockUseAlertTrendsQuery({
      data: {
        alertTrends: {
          // eslint-disable-next-line @typescript-eslint/naming-convention
          Low: [{x: '2024-01-10', y: 1}],
          // eslint-disable-next-line @typescript-eslint/naming-convention
          Medium: [{x: '2024-01-10', y: 2}],
          // eslint-disable-next-line @typescript-eslint/naming-convention
          High: [{x: '2024-01-10', y: 3}],
          // eslint-disable-next-line @typescript-eslint/naming-convention
          Critical: [{x: '2024-01-10', y: 4}],
        },
      },
    })

    render(
      <AlertTrendsChart
        query={query}
        startDate={startDate}
        endDate={endDate}
        isOpenSelected={false}
        grouping="severity"
      />,
    )

    expect(screen.getByText('Closed alerts over time')).toBeInTheDocument()
    expect(screen.getByTestId('chart-card')).toBeInTheDocument()
    expect(screen.getByTestId('grouping-selector')).toBeInTheDocument()
  })

  it('should render loading state', () => {
    mockUseAlertTrendsQuery({isSuccess: false, isPending: true, isError: false})

    render(
      <AlertTrendsChart query={query} startDate={startDate} endDate={endDate} isOpenSelected grouping="severity" />,
    )

    expect(screen.getByText('Open alerts over time')).toBeInTheDocument()
    expect(screen.getByTestId('loading-indicator')).toBeInTheDocument()
  })

  it('should render error state', () => {
    mockUseAlertTrendsQuery({isSuccess: false, isPending: false, isError: true})

    render(
      <AlertTrendsChart query={query} startDate={startDate} endDate={endDate} isOpenSelected grouping="severity" />,
    )

    expect(screen.getByText('Open alerts over time')).toBeInTheDocument()
    expect(screen.getByTestId('error')).toBeInTheDocument()
  })

  it('should render no-data state', () => {
    mockUseAlertTrendsQuery({
      data: {
        alertTrends: {
          // eslint-disable-next-line @typescript-eslint/naming-convention
          Low: [],
          // eslint-disable-next-line @typescript-eslint/naming-convention
          Medium: [],
          // eslint-disable-next-line @typescript-eslint/naming-convention
          High: [],
          // eslint-disable-next-line @typescript-eslint/naming-convention
          Critical: [],
        },
      },
    })

    render(
      <AlertTrendsChart query={query} startDate={startDate} endDate={endDate} isOpenSelected grouping="severity" />,
    )

    expect(screen.getByText('Open alerts over time')).toBeInTheDocument()
    expect(screen.getByTestId('no-data')).toBeInTheDocument()
  })

  it('should use the previous two days for the previous date range rather than a whole timeperiod', () => {
    expect(calculatePreviousTwoDays(startDate)).toStrictEqual({startDate: '2023-01-01', endDate: '2023-01-02'})
  })

  it('should use calculatePreviousTwoDays', () => {
    mockUseAlertTrendsQuery({})

    render(
      <AlertTrendsChart query={query} startDate={startDate} endDate={endDate} isOpenSelected grouping="severity" />,
    )

    expect(mockCalculatePreviousTwoDays).toHaveBeenCalled()
  })

  it('should render chart when there were alerts yesterday but zero alerts today', () => {
    // Create a scenario where there were alerts yesterday but all are resolved today (zero)
    mockUseAlertTrendsQuery({
      data: {
        alertTrends: {
          // eslint-disable-next-line @typescript-eslint/naming-convention
          Low: [
            {x: '2023-01-30', y: 10}, // Yesterday had alerts
            {x: '2023-01-31', y: 0}, // Today has 0 alerts (all resolved)
          ],
          // eslint-disable-next-line @typescript-eslint/naming-convention
          Medium: [
            {x: '2023-01-30', y: 20},
            {x: '2023-01-31', y: 0},
          ],
        },
      },
    })

    render(
      <AlertTrendsChart query={query} startDate={startDate} endDate={endDate} isOpenSelected grouping="severity" />,
    )

    // Verify the chart is displayed (not showing a blankslate)
    expect(
      screen.queryByText('Try modifying your filters to see the security impact on your organization.'),
    ).not.toBeInTheDocument()
    expect(screen.getByText('Open alerts over time')).toBeInTheDocument()
    expect(screen.getByTestId('chart-card')).toBeInTheDocument()
  })
})
