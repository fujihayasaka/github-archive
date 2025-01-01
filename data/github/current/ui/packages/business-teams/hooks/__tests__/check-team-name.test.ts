import {act, renderHook, waitFor} from '@testing-library/react'

import {useCheckBusinessTeamsName} from '../check-team-name'

const mockVerifiedFetch = jest.fn().mockName('verifiedFetchJSON')
jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetch(...args),
  }
})
const mockValidityChange = jest.fn()

describe('useCheckBusinessTeamsName', () => {
  jest.useFakeTimers()

  test('does not fetch until runCheck is called', async () => {
    const responsePayload = {team: 'secops'}
    mockVerifiedFetch.mockResolvedValue({status: 200, ok: true, json: async () => responsePayload})

    const {result} = renderHook(() => useCheckBusinessTeamsName(mockValidityChange))
    const [checkResult, runCheck] = result.current
    expect(checkResult.status).toBe('none')
    expect(mockVerifiedFetch).toHaveBeenCalledTimes(0)

    act(() => {
      runCheck({name: 'secops', businessSlug: 'github-inc'})
    })
    expect(result.current[0].status).toBe('none')

    jest.runAllTimers() // Trigger the debounced method

    await waitFor(() => expect(result.current[0].status).toBe('ok'))
    expect(mockVerifiedFetch).toHaveBeenCalledTimes(1)

    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      '/enterprises/github-inc/check_team_name?teamName=secops&teamOldSlug=',
    )
  })

  test('handles team name change', async () => {
    const responsePayload = {team: 'tnt'}
    mockVerifiedFetch.mockResolvedValue({status: 201, ok: true, json: async () => responsePayload})

    const {result} = renderHook(() => useCheckBusinessTeamsName(mockValidityChange))
    const [, runCheck] = result.current

    act(() => runCheck({name: 'tnt', businessSlug: 'github-inc', teamSlug: 'secops'}))

    jest.runAllTimers() // Trigger the debounced fetch

    await waitFor(() => expect(result.current[0].status).toBe('ok'))
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      '/enterprises/github-inc/check_team_name?teamName=tnt&teamOldSlug=secops',
    )
    expect(mockValidityChange).toHaveBeenCalledWith(true)
  })

  test('handles not found for an invalid enterprise', async () => {
    const responsePayload = {team: 'employees'}
    mockVerifiedFetch.mockResolvedValue({status: 404, ok: false, json: async () => responsePayload})

    const {result} = renderHook(() => useCheckBusinessTeamsName(mockValidityChange))
    const [, runCheck] = result.current

    act(() => runCheck({name: 'employees', businessSlug: 'unknown-enterprise'}))

    jest.runAllTimers() // Trigger the debounced fetch

    await waitFor(() => expect(result.current[0].status).toBe('not_found'))
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      '/enterprises/unknown-enterprise/check_team_name?teamName=employees&teamOldSlug=',
    )
    expect(mockValidityChange).toHaveBeenCalledWith(false)
  })

  test('handles team name is not changed', async () => {
    const responsePayload = {message: 'unchanged'}
    mockVerifiedFetch.mockResolvedValue({status: 200, ok: true, json: async () => responsePayload})

    const {result} = renderHook(() => useCheckBusinessTeamsName(mockValidityChange))
    const [, runCheck] = result.current

    act(() => runCheck({name: 'secops', businessSlug: 'github-inc', teamSlug: 'secops'}))

    jest.runAllTimers() // Trigger the debounced fetch

    await waitFor(() => expect(result.current[0].status).toBe('unchanged'))
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      '/enterprises/github-inc/check_team_name?teamName=secops&teamOldSlug=secops',
    )
    expect(mockValidityChange).toHaveBeenCalledWith(true)
  })

  test('handles team name is in use (response 422)', async () => {
    const responsePayload = {team: 'secops', error: 'is already taken'}
    mockVerifiedFetch.mockResolvedValue({status: 422, ok: false, json: async () => responsePayload})

    const {result} = renderHook(() => useCheckBusinessTeamsName(mockValidityChange))
    const [, runCheck] = result.current

    act(() => runCheck({name: 'secops', businessSlug: 'github-inc'}))

    jest.runAllTimers() // Trigger the debounced fetch

    await waitFor(() => expect(result.current[0].status).toBe('error'))
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      '/enterprises/github-inc/check_team_name?teamName=secops&teamOldSlug=',
    )
    expect(result.current[0].error).toBe('is already taken')
    expect(mockValidityChange).toHaveBeenCalledWith(false)
  })

  test('handles team name contains unsupported characters (response 422)', async () => {
    const responsePayload = {team: '%F0%9F%8E%83', error: 'contains unsupported characters'}
    mockVerifiedFetch.mockResolvedValue({status: 422, ok: false, json: async () => responsePayload})

    const {result} = renderHook(() => useCheckBusinessTeamsName(mockValidityChange))
    const [, runCheck] = result.current

    act(() => runCheck({name: '🎃', businessSlug: 'github-inc'}))

    jest.runAllTimers() // Trigger the debounced fetch

    await waitFor(() => expect(result.current[0].status).toBe('error'))
    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      '/enterprises/github-inc/check_team_name?teamName=%F0%9F%8E%83&teamOldSlug=',
    )
    expect(result.current[0].error).toBe('contains unsupported characters')
    expect(mockValidityChange).toHaveBeenCalledWith(false)
  })
})
