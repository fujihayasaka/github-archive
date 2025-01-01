// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {waitFor} from '@testing-library/react'

import {JSON_HEADER} from '../../../../common/utils/fetch-json'
import {renderHook} from '../../../../test-utils/render-hook'
import useRepositoriesQuery from '../use-repositories-query'

describe('useRepositoriesQuery', () => {
  const BASE_ROUTE = '/orgs/github/security/metrics/dependabot/repositories'
  const BASE_ROUTE_REGEX = new RegExp(BASE_ROUTE)

  const MOCK_RESPONSE = {
    items: [
      {
        id: 'github/foo',
        displayName: 'foo',
        href: `http://localhost/github/foo`,
        countOpen: Math.floor(Math.random() * 100),
        countEPSS: Math.floor(Math.random() * 100),
        countCritical: Math.floor(Math.random() * 100),
        countHigh: Math.floor(Math.random() * 100),
        countMedium: Math.floor(Math.random() * 100),
        countLow: Math.floor(Math.random() * 100),
      },
      {
        id: 'github/bar',
        displayName: 'bar',
        href: `http://localhost/github/bar`,
        countOpen: Math.floor(Math.random() * 100),
        countEPSS: Math.floor(Math.random() * 100),
        countCritical: Math.floor(Math.random() * 100),
        countHigh: Math.floor(Math.random() * 100),
        countMedium: Math.floor(Math.random() * 100),
        countLow: Math.floor(Math.random() * 100),
      },
    ],
    previous: null,
    next: 'some-opaque-value',
  }

  it('fetches data', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, MOCK_RESPONSE, {headers: new Headers(JSON_HEADER)})

    const {result} = renderHook(() =>
      useRepositoriesQuery({
        query: 'foobar',
        cursor: 'some-opaque-value',
        sort: {
          field: 'countOpen',
          direction: 'desc',
        },
      }),
    )

    expect(mock).toHaveBeenCalled()
    expect(mock).toHaveBeenCalledWith(
      `${BASE_ROUTE}?query=foobar&cursor=some-opaque-value&sortField=countOpen&sortDirection=desc`,
      expect.anything(),
    )
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toEqual(MOCK_RESPONSE)
  })

  it('omits empty query parameters', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, MOCK_RESPONSE, {headers: new Headers(JSON_HEADER)})

    const {result} = renderHook(() =>
      useRepositoriesQuery({
        query: 'foobar',
      }),
    )

    expect(mock).toHaveBeenCalled()
    expect(mock).toHaveBeenCalledWith(`${BASE_ROUTE}?query=foobar`, expect.anything())
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
  })

  it('returns error state if request fails', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, undefined, {status: 500})

    const {result} = renderHook(() =>
      useRepositoriesQuery({
        query: 'foobar',
      }),
    )

    expect(mock).toHaveBeenCalled()
    await waitFor(() => expect(result.current.isError).toBe(true))
    expect(result.current.data).toBeUndefined()
  })
})
