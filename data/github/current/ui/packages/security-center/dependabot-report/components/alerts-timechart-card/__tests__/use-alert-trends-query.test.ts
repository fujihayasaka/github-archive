// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {waitFor} from '@testing-library/react'

import {JSON_HEADER} from '../../../../common/utils/fetch-json'
import {renderHook} from '../../../../test-utils/render-hook'
import {useAlertTrendsQuery} from '../use-alert-trends-query'

describe('useAlertTrendsQuery', () => {
  const BASE_ROUTE = '/orgs/github/security/metrics/dependabot/alerts-funnel'
  const BASE_ROUTE_REGEX = new RegExp(BASE_ROUTE)

  const MOCK_RESPONSE = {
    label: 'Open Alerts',
    points: [
      {x: 'Matching Alerts', y: 500},
      {x: 'has:patch', y: 400},
      {x: 'severity:critical,high', y: 125},
      {x: 'epss_percentage:>=0.01', y: 20},
    ],
  }

  it('fetches data', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, MOCK_RESPONSE, {headers: new Headers(JSON_HEADER)})

    const {result} = renderHook(() =>
      useAlertTrendsQuery({
        query: 'foobar',
      }),
    )

    expect(mock).toHaveBeenCalled()
    expect(mock).toHaveBeenCalledWith(`${BASE_ROUTE}?query=foobar`, expect.anything())
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toEqual(MOCK_RESPONSE)
  })

  it('returns error state if request fails', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, undefined, {status: 500})

    const {result} = renderHook(() =>
      useAlertTrendsQuery({
        query: 'foobar',
      }),
    )

    expect(mock).toHaveBeenCalled()
    await waitFor(() => expect(result.current.isError).toBe(true))
    expect(result.current.data).toBeUndefined()
  })
})
