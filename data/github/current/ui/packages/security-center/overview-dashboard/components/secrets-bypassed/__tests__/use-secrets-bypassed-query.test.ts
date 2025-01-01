import {mockFetch} from '@github-ui/mock-fetch'
import {waitFor} from '@testing-library/react'

import {JSON_HEADER} from '../../../../common/utils/fetch-json'
import {renderHook} from '../../../../test-utils/render-hook'
import useSecretsBypassedQuery from '../use-secrets-bypassed-query'

describe('useSecretsBypassedQuery', () => {
  const BASE_ROUTE = '/orgs/github/security/overview/secrets-bypassed'
  const BASE_ROUTE_REGEX = new RegExp(BASE_ROUTE)

  const MOCK_RESPONSE = {
    isSucess: true,
    data: {
      result: {
        totalBlocksCount: 123,
        successfulBlocksCount: 456,
        bypassedAlertsCount: 789,
      },
    },
  }

  it('fetches data', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, MOCK_RESPONSE, {headers: new Headers(JSON_HEADER)})

    const {result} = renderHook(() =>
      useSecretsBypassedQuery({
        query: 'foobar',
        startDate: '2024-01-01',
        endDate: '2024-12-31',
      }),
    )

    expect(mock).toHaveBeenCalled()
    expect(mock).toHaveBeenCalledWith(
      `${BASE_ROUTE}?startDate=2024-01-01&endDate=2024-12-31&query=foobar`,
      expect.anything(),
    )
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toEqual(MOCK_RESPONSE)
  })

  it('returns error state if request fails', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, undefined, {status: 500})

    const {result} = renderHook(() =>
      useSecretsBypassedQuery({
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
      useSecretsBypassedQuery({query: '', startDate: '2021-01-01', endDate: '2021-12-31'}),
    )
    await waitFor(() => expect(result.current.isError).toEqual(true))
  })
})
