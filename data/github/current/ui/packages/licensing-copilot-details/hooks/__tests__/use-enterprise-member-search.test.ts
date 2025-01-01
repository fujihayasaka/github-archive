import {renderHook, waitFor} from '@testing-library/react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useEnterpriseMemberSearch} from '../use-enterprise-member-search'
import {usersWithoutCopilotAccess} from '../../test-utils/mock-data'

const mockVerifiedFetch = verifiedFetch as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

const basePath = '/test-enterprise'
const users = usersWithoutCopilotAccess

beforeEach(() => {
  jest.clearAllMocks()
})

describe('useEnterpriseMemberSearch', () => {
  test('initializes with empty state', () => {
    const {result} = renderHook(() => useEnterpriseMemberSearch(basePath, ''))

    expect(result.current.users).toEqual([])
    expect(result.current.loading).toBe(false)
    expect(result.current.isEmpty).toBe(true)
    expect(result.current.hasQuery).toBe(false)
  })

  test('fetches users when search query is provided', async () => {
    mockVerifiedFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({withoutCopilotAccess: users}),
    } as Response)

    const {result} = renderHook(() => useEnterpriseMemberSearch(basePath, 'github'))

    expect(result.current.loading).toBe(true)

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })

    expect(mockVerifiedFetch).toHaveBeenCalledWith(`${basePath}/enterprise_licensing/user_licenses?query=github`, {
      method: 'GET',
      headers: {Accept: 'application/json'},
    })
    expect(result.current.users).toEqual(users)
    expect(result.current.isEmpty).toBe(false)
    expect(result.current.hasQuery).toBe(true)
  })

  test('handles empty search results', async () => {
    mockVerifiedFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({withoutCopilotAccess: []}),
    } as Response)

    const {result} = renderHook(() => useEnterpriseMemberSearch(basePath, 'nonexistent'))

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })

    expect(result.current.users).toEqual([])
    expect(result.current.isEmpty).toBe(true)
    expect(result.current.hasQuery).toBe(true)
  })

  test('does not fetch when search query is empty', async () => {
    const {result} = renderHook(() => useEnterpriseMemberSearch(basePath, ''))

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })

    expect(mockVerifiedFetch).not.toHaveBeenCalled()
    expect(result.current.users).toEqual([])
    expect(result.current.isEmpty).toBe(true)
    expect(result.current.hasQuery).toBe(false)
  })

  test('handles API errors gracefully', async () => {
    mockVerifiedFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
    } as Response)

    const {result} = renderHook(() => useEnterpriseMemberSearch(basePath, 'github'))

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })

    expect(result.current.users).toEqual([])
    expect(result.current.isEmpty).toBe(true)
    expect(result.current.hasQuery).toBe(true)
  })

  test('updates results when search query changes', async () => {
    const {result, rerender} = renderHook(({query}) => useEnterpriseMemberSearch(basePath, query), {
      initialProps: {query: ''},
    })

    expect(result.current.users).toEqual([])

    // Update search query
    mockVerifiedFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({withoutCopilotAccess: users}),
    } as Response)

    rerender({query: 'github'})

    await waitFor(() => {
      expect(result.current.loading).toBe(false)
    })

    expect(result.current.users).toEqual(users)
    expect(result.current.hasQuery).toBe(true)
  })

  test('clears results when search query is cleared', async () => {
    // Start with a query
    mockVerifiedFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({withoutCopilotAccess: users}),
    } as Response)

    const {result, rerender} = renderHook(({query}) => useEnterpriseMemberSearch(basePath, query), {
      initialProps: {query: 'github'},
    })

    await waitFor(() => {
      expect(result.current.users).toEqual(users)
    })

    // Clear the query
    rerender({query: ''})

    await waitFor(() => {
      expect(result.current.users).toEqual([])
    })

    expect(result.current.isEmpty).toBe(true)
    expect(result.current.hasQuery).toBe(false)
  })
})
