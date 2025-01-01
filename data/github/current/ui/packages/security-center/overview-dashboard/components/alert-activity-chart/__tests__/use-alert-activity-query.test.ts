// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {waitFor} from '@testing-library/react'

import {JSON_HEADER} from '../../../../common/utils/fetch-json'
import {renderHook} from '../../../../test-utils/render-hook'
import {useAlertActivityQuery} from '../../alert-activity-chart/use-alert-activity-query'

// This mock represents the data returned from a _single_ fetch within the useQueries() hook.
const MOCK_RESPONSE = {
  isSuccess: true,
  data: {
    data: [
      {
        opened: 10,
        closed: 4,
        date: 'Oct 1',
        endDate: 'Oct 31',
      },
      {
        opened: 5,
        closed: 2,
        date: 'Nov 1',
        endDate: 'Nov 30',
      },
    ],
  },
}

const BASE_ROUTE = '/orgs/github/security/overview/alert-activity'
const BASE_ROUTE_REGEX = new RegExp(BASE_ROUTE)

describe('useAlertActivityQuery', () => {
  it('fetches data for each tool', async () => {
    const mock = mockFetch.mockRoute(BASE_ROUTE_REGEX, MOCK_RESPONSE, {
      headers: new Headers(JSON_HEADER),
    })

    const {result} = renderHook(() =>
      useAlertActivityQuery({
        query: 'foobar',
        startDate: '2024-01-01',
        endDate: '2024-12-31',
      }),
    )

    expect(mock).toHaveBeenCalledTimes(3)
    expect(mock).toHaveBeenCalledWith(
      `${BASE_ROUTE}?startDate=2024-01-01&endDate=2024-12-31&query=foobar+tool%3Asecret-scanning`,
      expect.anything(),
    )
    expect(mock).toHaveBeenCalledWith(
      `${BASE_ROUTE}?startDate=2024-01-01&endDate=2024-12-31&query=foobar+tool%3Adependabot`,
      expect.anything(),
    )
    expect(mock).toHaveBeenCalledWith(
      `${BASE_ROUTE}?startDate=2024-01-01&endDate=2024-12-31&query=foobar+tool%3Acodeql%2Cthird-party`,
      expect.anything(),
    )

    await waitFor(() => expect(result.current.every(data => data.isSuccess)).toBe(true))
    expect(result.current.length).toBe(3)
    expect(result.current[0]?.data).toEqual(MOCK_RESPONSE)
    expect(result.current[1]?.data).toEqual(MOCK_RESPONSE)
    expect(result.current[2]?.data).toEqual(MOCK_RESPONSE)
  })

  it('returns error state if date is more than two years in the past', async () => {
    const {result} = renderHook(() =>
      useAlertActivityQuery({query: '', startDate: '2021-01-01', endDate: '2021-12-31'}),
    )
    await waitFor(() => {
      result.current.every(r => expect(r.isError).toEqual(true))
    })
  })
})
