import {mockFetch} from '@github-ui/mock-fetch'
import {waitFor} from '@testing-library/react'

import {JSON_HEADER} from '../../../../common/utils/fetch-json'
import {renderHook} from '../../../../test-utils/render-hook'
import {getAlertTrendsData, getTotalAlertCountData, useAlertTrendsQuery} from '../use-alert-trends-query'

// These mocks represent the data returned from a _single_ fetch within the useQueries() hook.
const MOCK_RESPONSE_BY_SEVERITY = {
  isSuccess: true,
  data: {
    alertTrends: {
      // eslint-disable-next-line @typescript-eslint/naming-convention
      Low: [
        {x: '2024-01-09', y: 100},
        {x: '2024-01-10', y: 1},
      ],
      // eslint-disable-next-line @typescript-eslint/naming-convention
      Medium: [
        {x: '2024-01-09', y: 200},
        {x: '2024-01-10', y: 2},
      ],
      // eslint-disable-next-line @typescript-eslint/naming-convention
      High: [
        {x: '2024-01-09', y: 300},
        {x: '2024-01-10', y: 3},
      ],
      // eslint-disable-next-line @typescript-eslint/naming-convention
      Critical: [
        {x: '2024-01-09', y: 400},
        {x: '2024-01-10', y: 4},
      ],
    },
  },
}
const MOCK_RESPONSE_BY_AGE = {
  isSuccess: true,
  alertTrends: {
    '< 30 days': [
      {x: '2024-01-09', y: 100},
      {x: '2024-01-10', y: 1},
    ],

    '31 - 59 days': [
      {x: '2024-01-09', y: 200},
      {x: '2024-01-10', y: 2},
    ],

    '60 - 89 days': [
      {x: '2024-01-09', y: 300},
      {x: '2024-01-10', y: 3},
    ],
    '90+ days': [
      {x: '2024-01-09', y: 400},
      {x: '2024-01-10', y: 4},
    ],
  },
}
const MOCK_RESPONSE_BY_TOOL = [
  {
    isSuccess: true,
    alertTrends: {
      // eslint-disable-next-line @typescript-eslint/naming-convention
      Dependabot: [
        {x: '2024-01-09', y: 100},
        {x: '2024-01-10', y: 1},
      ],
    },
  },
  {
    isSuccess: true,
    alertTrends: {
      'Secret scanning': [
        {x: '2024-01-09', y: 100},
        {x: '2024-01-10', y: 1},
      ],
    },
  },
  {
    isSuccess: true,
    alertTrends: {
      // eslint-disable-next-line @typescript-eslint/naming-convention
      CodeQL: [
        {x: '2024-01-09', y: 100},
        {x: '2024-01-10', y: 1},
      ],
    },
  },
]

const BASE_ROUTE_BY_SEVERITY = '/orgs/github/security/overview/alert-trends-by-severity'
const BASE_ROUTE_BY_AGE = '/orgs/github/security/overview/alert-trends-by-age'
const BASE_ROUTE_BY_TOOL = '/orgs/github/security/overview/alert-trends-by-tool'
const BASE_ROUTE_BY_SEVERITY_REGEX = new RegExp(BASE_ROUTE_BY_SEVERITY)
const BASE_ROUTE_BY_AGE_REGEX = new RegExp(BASE_ROUTE_BY_AGE)
const BASE_ROUTE_BY_TOOL_REGEX = new RegExp(BASE_ROUTE_BY_TOOL)

describe('useAlertTrendsQuery', () => {
  describe('without query slicing', () => {
    it('fetches data for severity grouping', async () => {
      const mock = mockFetch.mockRoute(BASE_ROUTE_BY_SEVERITY_REGEX, MOCK_RESPONSE_BY_SEVERITY, {
        headers: new Headers(JSON_HEADER),
      })

      const {result} = renderHook(() =>
        useAlertTrendsQuery({
          query: 'foobar',
          startDate: '2024-01-01',
          endDate: '2024-12-31',
          grouping: 'severity',
          alertState: 'open',
        }),
      )

      expect(mock).toHaveBeenCalled()
      expect(mock).toHaveBeenCalledWith(
        `${BASE_ROUTE_BY_SEVERITY}?alertTrendsChart%5BisOpenSelected%5D=true&query=foobar+tool%3Asecret-scanning&startDate=2024-01-01&endDate=2024-12-31`,
        expect.anything(),
      )
      expect(mock).toHaveBeenCalledWith(
        `${BASE_ROUTE_BY_SEVERITY}?alertTrendsChart%5BisOpenSelected%5D=true&query=foobar+tool%3Adependabot&startDate=2024-01-01&endDate=2024-12-31`,
        expect.anything(),
      )
      expect(mock).toHaveBeenCalledWith(
        `${BASE_ROUTE_BY_SEVERITY}?alertTrendsChart%5BisOpenSelected%5D=true&query=foobar+tool%3Acodeql%2Cthird-party&startDate=2024-01-01&endDate=2024-12-31`,
        expect.anything(),
      )
      // Each fetch returns a single dataset, but useQueries() will return all of them as an array of query results.
      await waitFor(() => expect(result.current.every(data => data.isSuccess)).toBe(true))
      expect(result.current.length).toBe(3)
      expect(result.current[0]?.data).toEqual(MOCK_RESPONSE_BY_SEVERITY)
      expect(result.current[1]?.data).toEqual(MOCK_RESPONSE_BY_SEVERITY)
      expect(result.current[2]?.data).toEqual(MOCK_RESPONSE_BY_SEVERITY)
    })

    it('fetches data for age grouping', async () => {
      const mock = mockFetch.mockRoute(BASE_ROUTE_BY_AGE_REGEX, MOCK_RESPONSE_BY_AGE, {
        headers: new Headers(JSON_HEADER),
      })

      const {result} = renderHook(() =>
        useAlertTrendsQuery({
          query: 'foobar',
          startDate: '2024-01-01',
          endDate: '2024-12-31',
          grouping: 'age',
          alertState: 'open',
        }),
      )

      expect(mock).toHaveBeenCalled()
      expect(mock).toHaveBeenCalledWith(
        `${BASE_ROUTE_BY_AGE}?alertTrendsChart%5BisOpenSelected%5D=true&query=foobar+tool%3Asecret-scanning&startDate=2024-01-01&endDate=2024-12-31`,
        expect.anything(),
      )
      expect(mock).toHaveBeenCalledWith(
        `${BASE_ROUTE_BY_AGE}?alertTrendsChart%5BisOpenSelected%5D=true&query=foobar+tool%3Adependabot&startDate=2024-01-01&endDate=2024-12-31`,
        expect.anything(),
      )
      expect(mock).toHaveBeenCalledWith(
        `${BASE_ROUTE_BY_AGE}?alertTrendsChart%5BisOpenSelected%5D=true&query=foobar+tool%3Acodeql%2Cthird-party&startDate=2024-01-01&endDate=2024-12-31`,
        expect.anything(),
      )
      await waitFor(() => expect(result.current.every(data => data.isSuccess)).toBe(true))
      expect(result.current.length).toBe(3)
      expect(result.current[0]?.data).toEqual(MOCK_RESPONSE_BY_AGE)
      expect(result.current[1]?.data).toEqual(MOCK_RESPONSE_BY_AGE)
      expect(result.current[2]?.data).toEqual(MOCK_RESPONSE_BY_AGE)
    })

    it('fetches data for tool grouping', async () => {
      const mock = mockFetch.mockRoute(BASE_ROUTE_BY_TOOL_REGEX, MOCK_RESPONSE_BY_TOOL, {
        headers: new Headers(JSON_HEADER),
      })

      const {result} = renderHook(() =>
        useAlertTrendsQuery({
          query: 'foobar',
          startDate: '2024-01-01',
          endDate: '2024-12-31',
          grouping: 'tool',
          alertState: 'open',
        }),
      )

      expect(mock).toHaveBeenCalled()
      expect(mock).toHaveBeenCalledWith(
        `${BASE_ROUTE_BY_TOOL}-secret-scanning?alertTrendsChart%5BisOpenSelected%5D=true&query=foobar+tool%3Asecret-scanning&startDate=2024-01-01&endDate=2024-12-31`,
        expect.anything(),
      )
      expect(mock).toHaveBeenCalledWith(
        `${BASE_ROUTE_BY_TOOL}-dependabot-alerts?alertTrendsChart%5BisOpenSelected%5D=true&query=foobar+tool%3Adependabot&startDate=2024-01-01&endDate=2024-12-31`,
        expect.anything(),
      )
      expect(mock).toHaveBeenCalledWith(
        `${BASE_ROUTE_BY_TOOL}-code-scanning?alertTrendsChart%5BisOpenSelected%5D=true&query=foobar+tool%3Acodeql%2Cthird-party&startDate=2024-01-01&endDate=2024-12-31`,
        expect.anything(),
      )
      await waitFor(() => expect(result.current.every(data => data.isSuccess)).toBe(true))
      expect(result.current.length).toBe(3)
      expect(result.current[0]?.data).toEqual(MOCK_RESPONSE_BY_TOOL)
      expect(result.current[1]?.data).toEqual(MOCK_RESPONSE_BY_TOOL)
      expect(result.current[2]?.data).toEqual(MOCK_RESPONSE_BY_TOOL)
    })

    it('fetches data for closed alert state', async () => {
      const mock = mockFetch.mockRoute(BASE_ROUTE_BY_SEVERITY_REGEX, MOCK_RESPONSE_BY_SEVERITY, {
        headers: new Headers(JSON_HEADER),
      })

      const {result} = renderHook(() =>
        useAlertTrendsQuery({
          query: 'foobar',
          startDate: '2024-01-01',
          endDate: '2024-12-31',
          grouping: 'severity',
          alertState: 'closed',
        }),
      )

      expect(mock).toHaveBeenCalled()
      expect(mock).toHaveBeenCalledWith(
        `${BASE_ROUTE_BY_SEVERITY}?alertTrendsChart%5BisOpenSelected%5D=false&query=foobar+tool%3Asecret-scanning&startDate=2024-01-01&endDate=2024-12-31`,
        expect.anything(),
      )
      expect(mock).toHaveBeenCalledWith(
        `${BASE_ROUTE_BY_SEVERITY}?alertTrendsChart%5BisOpenSelected%5D=false&query=foobar+tool%3Adependabot&startDate=2024-01-01&endDate=2024-12-31`,
        expect.anything(),
      )
      expect(mock).toHaveBeenCalledWith(
        `${BASE_ROUTE_BY_SEVERITY}?alertTrendsChart%5BisOpenSelected%5D=false&query=foobar+tool%3Acodeql%2Cthird-party&startDate=2024-01-01&endDate=2024-12-31`,
        expect.anything(),
      )
      await waitFor(() => expect(result.current.every(data => data.isSuccess)).toBe(true))
      expect(result.current.length).toBe(3)
      expect(result.current[0]?.data).toEqual(MOCK_RESPONSE_BY_SEVERITY)
      expect(result.current[1]?.data).toEqual(MOCK_RESPONSE_BY_SEVERITY)
      expect(result.current[2]?.data).toEqual(MOCK_RESPONSE_BY_SEVERITY)
    })

    it('returns error state if request fails', async () => {
      const mock = mockFetch.mockRoute(BASE_ROUTE_BY_SEVERITY_REGEX, undefined, {status: 500})

      const {result} = renderHook(() =>
        useAlertTrendsQuery({
          query: 'foobar',
          startDate: '2024-01-01',
          endDate: '2024-12-31',
          grouping: 'severity',
          alertState: 'closed',
        }),
      )

      expect(mock).toHaveBeenCalled()
      await waitFor(() => expect(result.current.every(data => data.isError)).toBe(true))
      expect(result.current[0]?.data).toBeUndefined()
    })
  })

  it('returns error state if date is more than two years in the past', async () => {
    const {result} = renderHook(() =>
      useAlertTrendsQuery({
        query: '',
        startDate: '2021-01-01',
        endDate: '2021-12-31',
        grouping: 'severity',
        alertState: 'open',
      }),
    )
    await waitFor(() => {
      result.current.every(r => expect(r.isError).toEqual(true))
    })
  })
})

describe('useAlertTrendsData', () => {
  it('combines data from each tool', () => {
    // Mock response from 3 parallel fetches, each with data for 4 severities.
    const mockFetchResults = new Array(3).fill(MOCK_RESPONSE_BY_SEVERITY)
    const expectedData = new Map([
      [
        'Low',
        [
          {x: '2024-01-09', y: 300},
          {x: '2024-01-10', y: 3},
        ],
      ],
      [
        'Medium',
        [
          {x: '2024-01-09', y: 600},
          {x: '2024-01-10', y: 6},
        ],
      ],
      [
        'High',
        [
          {x: '2024-01-09', y: 900},
          {x: '2024-01-10', y: 9},
        ],
      ],
      [
        'Critical',
        [
          {x: '2024-01-09', y: 1200},
          {x: '2024-01-10', y: 12},
        ],
      ],
    ])

    const combinedData = getAlertTrendsData(mockFetchResults)
    expect(combinedData).toEqual(expectedData)
  })

  it('returns an empty mapping if fetch is not successful', () => {
    const mockFetchResults = new Array(3).fill({isSuccess: false})
    const combinedData = getAlertTrendsData(mockFetchResults)

    expect(combinedData.size).toBe(0)
  })
})

describe('useTotalAlertCountData', () => {
  it('returns total count of all data points', () => {
    const mockFetchResults = new Array(3).fill(MOCK_RESPONSE_BY_SEVERITY)
    const expected = 30 // 3 + 6 + 9 + 12
    const total = getTotalAlertCountData(mockFetchResults)

    expect(total).toEqual(expected)
  })

  it('returns 0 if fetch is not succesful', () => {
    const mockFetchResults = new Array(3).fill({isSuccess: false})
    const total = getTotalAlertCountData(mockFetchResults)

    expect(total).toBe(0)
  })

  it('returns 0 if there are no data points', () => {
    const mockFetchResults = new Array(3).fill({isSuccess: true, data: {}})
    for (const result of mockFetchResults) {
      result.data.alertTrends = new Map([
        ['Low', []],
        ['Medium', []],
        ['High', []],
        ['Critical', []],
      ])
    }
    const total = getTotalAlertCountData(mockFetchResults)

    expect(total).toBe(0)
  })
})
