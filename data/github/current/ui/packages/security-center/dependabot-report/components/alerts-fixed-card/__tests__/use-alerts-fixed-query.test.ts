// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {waitFor} from '@testing-library/react'

import {JSON_HEADER} from '../../../../common/utils/fetch-json'
import {renderHook} from '../../../../test-utils/render-hook'
import useAlertsFixedQuery from '../use-alerts-fixed-query'

describe('useAlertsFixedQuery', () => {
  const BASE_ROUTE = '/orgs/github/security/metrics/dependabot/alerts-fixed'
  const BASE_ROUTE_REGEX = new RegExp(BASE_ROUTE)

  const MOCK_RESPONSE = {
    count: 32446,
    matching: 43446,
    percentage: 74.693,
  }

  it('fetches data', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, MOCK_RESPONSE, {headers: new Headers(JSON_HEADER)})

    const {result} = renderHook(() =>
      useAlertsFixedQuery({
        query: 'state:fixed',
      }),
    )

    expect(mock).toHaveBeenCalled()
    expect(mock).toHaveBeenCalledWith(`${BASE_ROUTE}?query=state%3Afixed`, expect.anything())
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toEqual(MOCK_RESPONSE)
  })

  it('returns error state if request fails', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, undefined, {status: 500})

    const {result} = renderHook(() =>
      useAlertsFixedQuery({
        query: 'state:fixed',
      }),
    )

    expect(mock).toHaveBeenCalled()
    await waitFor(() => expect(result.current.isError).toBe(true))
    expect(result.current.data).toBeUndefined()
  })
})
