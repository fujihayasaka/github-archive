import {mockFetch} from '@github-ui/mock-fetch'
import type {UseQueryResult} from '@tanstack/react-query'
import {waitFor} from '@testing-library/react'

import {JSON_HEADER} from '../../../../common/utils/fetch-json'
import {renderHook} from '../../../../test-utils/render-hook'
import {
  getTotalAlertCountData,
  type PreventedAndIntroducedResult,
  usePreventedAndIntroducedChartData,
} from '../use-prevented-and-introduced-chart-data'

const MOCK_RESPONSE = [
  {
    label: 'Introduced',
    data: [
      {x: '2024-06-25', y: 100},
      {x: '2024-06-25', y: 200},
    ],
  },
  {
    label: 'Prevented',
    data: [
      {x: '2024-06-25', y: 300},
      {x: '2024-06-25', y: 400},
    ],
  },
]

describe('usePreventedAndIntroducedChartData', () => {
  const BASE_ROUTE = '/orgs/github/security/overview/introduced-prevented'
  const BASE_ROUTE_REGEX = new RegExp(BASE_ROUTE)

  it('fetches data', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, MOCK_RESPONSE, {headers: new Headers(JSON_HEADER)})

    const {result} = renderHook(() =>
      usePreventedAndIntroducedChartData({
        query: 'foobar',
        startDate: '2024-01-01',
        endDate: '2024-12-31',
      }),
    )

    expect(mock).toHaveBeenCalled()
    expect(mock).toHaveBeenCalledWith(
      `${BASE_ROUTE}?query=foobar&startDate=2024-01-01&endDate=2024-12-31`,
      expect.anything(),
    )
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toEqual(MOCK_RESPONSE)
  })

  it('returns error state if request fails', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, undefined, {status: 500})

    const {result} = renderHook(() =>
      usePreventedAndIntroducedChartData({
        query: 'foobar',
        startDate: '2024-01-01',
        endDate: '2024-12-31',
      }),
    )

    expect(mock).toHaveBeenCalled()
    await waitFor(() => expect(result.current.isError).toBe(true))
    expect(result.current.data).toBeUndefined()
  })

  it('returns error state if date is more than two years in the past', async () => {
    const {result} = renderHook(() =>
      usePreventedAndIntroducedChartData({query: '', startDate: '2021-01-01', endDate: '2021-12-31'}),
    )
    await waitFor(() => expect(result.current.isError).toEqual(true))
  })
})

describe('useTotalAlertCountData', () => {
  it('returns the total alert count from all series', () => {
    const mockResult = {
      isSuccess: true,
      data: MOCK_RESPONSE,
    } as UseQueryResult<PreventedAndIntroducedResult>

    const result = getTotalAlertCountData(mockResult)
    expect(result).toBe(1000)
  })

  it('returns 0 if result is not successful', () => {
    const mockResult = {
      isSuccess: false,
      data: MOCK_RESPONSE,
    } as UseQueryResult<PreventedAndIntroducedResult>

    const result = getTotalAlertCountData(mockResult)
    expect(result).toBe(0)
  })

  it('returns 0 if data is empty', () => {
    const mockResult = {
      isSuccess: true,
      data: [] as PreventedAndIntroducedResult,
    } as UseQueryResult<PreventedAndIntroducedResult>

    const result = getTotalAlertCountData(mockResult)
    expect(result).toBe(0)
  })

  it('returns 0 if all series counts are 0', () => {
    const mockResult = {
      isSuccess: true,
      data: [
        {
          label: 'Introduced',
          data: [
            {x: '2024-06-25', y: 0},
            {x: '2024-06-25', y: 0},
          ],
        },
        {
          label: 'Prevented',
          data: [
            {x: '2024-06-25', y: 0},
            {x: '2024-06-25', y: 0},
          ],
        },
      ],
    } as UseQueryResult<PreventedAndIntroducedResult>

    const result = getTotalAlertCountData(mockResult)
    expect(result).toBe(0)
  })
})
