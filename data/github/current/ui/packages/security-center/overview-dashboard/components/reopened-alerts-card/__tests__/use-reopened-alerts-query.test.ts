import {mockFetch} from '@github-ui/mock-fetch'
import type {UseQueryResult} from '@github-ui/react-query'
import {waitFor} from '@testing-library/react'

import {JSON_HEADER} from '../../../../common/utils/fetch-json'
import {renderHook} from '../../../../test-utils/render-hook'
import {
  getTrend,
  type ReopenedAlertsResult,
  resultsReducer,
  useReopenedAlertsQuery,
} from '../../reopened-alerts-card/use-reopened-alerts-query'

afterEach(() => {
  jest.clearAllMocks()
})

const BASE_ROUTE = '/orgs/github/security/overview/reopened-alerts'
const BASE_ROUTE_REGEX = new RegExp(BASE_ROUTE)

const MOCK_RESPONSE = {
  isSuccess: true,
  data: {
    count: 500,
  },
}

const startDate = '2024-01-01'
const endDate = '2024-12-31'
const query = 'foobar'

describe('useReopenedAlertsQuery', () => {
  it('fetches data for each tool', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, MOCK_RESPONSE, {
      headers: new Headers(JSON_HEADER),
    })

    renderHook(() => useReopenedAlertsQuery({query, startDate, endDate}))

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
      useReopenedAlertsQuery({query: '', startDate: '2021-01-01', endDate: '2021-12-31'}),
    )
    await waitFor(() => expect(result.current.isError).toEqual(true))
  })
})

describe('resultsReducer', () => {
  it('returns the correct data from a single fetch', () => {
    const mockResult = [MOCK_RESPONSE] as Array<UseQueryResult<ReopenedAlertsResult>>
    const data = resultsReducer(mockResult)

    expect(data).toEqual({
      count: 500,
      isSuccess: true,
      isPending: false,
      isError: false,
    })
  })

  it('returns the correct data from parallel queries', () => {
    const mockFetchResult = {
      isSuccess: true,
      data: {
        count: 2,
      },
    }
    const mockResult = new Array(3).fill(mockFetchResult) as Array<UseQueryResult<ReopenedAlertsResult>>
    const data = resultsReducer(mockResult)

    expect(data).toEqual({
      count: 6,
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
