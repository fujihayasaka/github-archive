// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import type {UseQueryResult} from '@github-ui/react-query'
import {waitFor} from '@testing-library/react'

import {JSON_HEADER} from '../../../../common/utils/fetch-json'
import {renderHook} from '../../../../test-utils/render-hook'
import {
  getTrend,
  type NetResolveRateResult,
  resultsReducer,
  useNetResolveRateQuery,
} from '../use-net-resolve-rate-query'

afterEach(() => {
  jest.clearAllMocks()
})

const BASE_ROUTE = '/orgs/github/security/overview/net-resolve-rate'
const BASE_ROUTE_REGEX = new RegExp(BASE_ROUTE)

const MOCK_RESPONSE = {
  isSuccess: true,
  data: {
    count: 500,
    openCount: 0,
    closedCount: 0,
  },
}

const startDate = '2024-01-01'
const endDate = '2024-12-31'
const query = 'foobar'

describe('useNetResolveRateQuery', () => {
  it('fetches data for each tool', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, MOCK_RESPONSE, {
      headers: new Headers(JSON_HEADER),
    })

    renderHook(() => useNetResolveRateQuery({query, startDate, endDate}))

    expect(mock).toHaveBeenCalledTimes(3)
    expect(mock).toHaveBeenCalledWith(
      `${BASE_ROUTE}?startDate=2024-01-01&endDate=2024-12-31&query=foobar+tool%3Asecret-scanning`,
      expect.anything(),
    )
    expect(mock).toHaveBeenCalledWith(
      `${BASE_ROUTE}?startDate=2024-01-01&endDate=2024-12-31&query=foobar+tool%3Asecret-scanning`,
      expect.anything(),
    )
    expect(mock).toHaveBeenCalledWith(
      `${BASE_ROUTE}?startDate=2024-01-01&endDate=2024-12-31&query=foobar+tool%3Asecret-scanning`,
      expect.anything(),
    )
  })

  it('returns error state if date is more than two years in the past', async () => {
    const {result} = renderHook(() =>
      useNetResolveRateQuery({query: '', startDate: '2021-01-01', endDate: '2021-12-31'}),
    )
    await waitFor(() => expect(result.current.isError).toEqual(true))
  })
})

describe('resultsReducer', () => {
  it('returns the correct data from a single fetch', () => {
    const mockFetchResult = {
      isSuccess: true,
      data: {
        openCount: 200,
        closedCount: 100,
      },
    }
    const mockResult = [mockFetchResult] as Array<UseQueryResult<NetResolveRateResult>>
    const data = resultsReducer(mockResult)

    expect(data).toEqual({
      count: 50,
      isSuccess: true,
      isPending: false,
      isError: false,
    })
  })

  it('returns the correct data from parallel queries', () => {
    const mockFetchResult = {
      isSuccess: true,
      data: {
        openCount: 2,
        closedCount: 1,
      },
    }
    const mockResult = new Array(3).fill(mockFetchResult) as Array<UseQueryResult<NetResolveRateResult>>
    const data = resultsReducer(mockResult)

    expect(data).toEqual({
      count: 50,
      isSuccess: true,
      isPending: false,
      isError: false,
    })
  })
})

describe('getTrend', () => {
  it('returns calculated trend when both periods are successful', () => {
    const currentPeriodData = {
      count: 1,
      isSuccess: true,
      isPending: false,
      isError: false,
    }
    const previousPeriodData = {
      count: 2,
      isSuccess: true,
      isPending: false,
      isError: false,
    }

    const trend = getTrend(currentPeriodData, previousPeriodData)
    expect(trend).toEqual(-50)
  })

  it('returns 0 when one of the periods is not successful', () => {
    const currentPeriodData = {
      count: 1,
      isSuccess: false,
      isPending: false,
      isError: false,
    }
    const previousPeriodData = {
      count: 2,
      isSuccess: true,
      isPending: false,
      isError: false,
    }

    const trend = getTrend(currentPeriodData, previousPeriodData)
    expect(trend).toEqual(0)
  })
})
