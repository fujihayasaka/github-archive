// eslint-disable-next-line @github-ui/github-monorepo/filename-convention, no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {act, renderHook, waitFor} from '@testing-library/react'

import useBudgetsPage from '../../hooks/budget/use-budgets-page'

import {MOCK_BUDGETS} from '../../test-utils/mock-data'

jest.mock('@github-ui/ssr-utils', () => ({
  get ssrSafeLocation() {
    return jest.fn().mockImplementation(() => {
      return {origin: 'https://github.localhost', pathname: '/enterprises/github-inc/billing'}
    })()
  },
}))

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: jest.fn().mockReturnValue({business: 'github-inc'}),
}))

describe('useBudgetsPage', () => {
  beforeEach(() => {
    mockFetch.mockRouteOnce(`/enterprises/github-inc/billing/budgets`, {
      payload: {budgets: MOCK_BUDGETS},
    })
  })

  it('Returns budget data when the response status code is 200', async () => {
    const {result} = renderHook(() => useBudgetsPage())

    await waitFor(() => expect(result.current.budgets.length).toEqual(1))
  })

  it('Delete budget from local state', async () => {
    const {result} = renderHook(() => useBudgetsPage())

    act(() => {
      result.current.deleteBudgetFromPage(result.current.budgets?.[0]?.uuid ?? '')
    })
    await waitFor(() => expect(result.current.budgets.length).toEqual(0))
  })
})
