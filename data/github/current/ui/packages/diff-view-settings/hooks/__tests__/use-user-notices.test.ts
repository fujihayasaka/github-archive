import {isLoggedIn} from '@github-ui/client-env'
import {dismissUserNoticePath} from '@github-ui/paths'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {act, renderHook} from '@testing-library/react'

import {useDismissNotice, useIsNoticeDismissed, useUserNotices} from '../use-user-notices'

// Mock dependencies
jest.mock('@github-ui/client-env', () => ({
  isLoggedIn: jest.fn(),
}))
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))
jest.mock('@github-ui/react-core/use-route-payload', () => ({
  useRoutePayload: jest.fn(),
}))
jest.mock('@github-ui/paths', () => ({
  dismissUserNoticePath: jest.fn(),
}))

afterEach(() => {
  jest.clearAllMocks()
})

describe('useUserNotices', () => {
  it('should return only active notices', () => {
    const mockPayload = {
      userNotices: [{name: 'compact_diff_lines', dismissed: false}],
    }
    ;(useRoutePayload as jest.Mock).mockReturnValue(mockPayload)

    const {result} = renderHook(() => useUserNotices())

    expect(result.current).toEqual([{name: 'compact_diff_lines', dismissed: false}])
  })
})

describe('useIsNoticeDismissed', () => {
  it('should return true if the notice is dismissed', () => {
    const mockPayload = {
      userNotices: [{name: 'compact_diff_lines', dismissed: true}],
    }
    ;(useRoutePayload as jest.Mock).mockReturnValue(mockPayload)

    const {result} = renderHook(() => useIsNoticeDismissed('compact_diff_lines'))

    expect(result.current).toBe(true)
  })

  it('should return false if the notice is not dismissed', () => {
    const mockPayload = {
      userNotices: [{name: 'compact_diff_lines', dismissed: false}],
    }
    ;(useRoutePayload as jest.Mock).mockReturnValue(mockPayload)

    const {result} = renderHook(() => useIsNoticeDismissed('compact_diff_lines'))

    expect(result.current).toBe(false)
  })

  // this is to ensure we don't show notices that are not in the payload
  it('should return true if the notice is not found', () => {
    const mockPayload = {
      userNotices: [],
    }
    ;(useRoutePayload as jest.Mock).mockReturnValue(mockPayload)

    const {result} = renderHook(() => useIsNoticeDismissed('compact_diff_lines'))

    expect(result.current).toBe(true)
  })
})

describe('useDismissNotice', () => {
  it('should call verifiedFetch to dismiss the notice if user is logged in and notice is not dismissed', () => {
    ;(isLoggedIn as jest.Mock).mockReturnValue(true)
    const mockPayload = {
      userNotices: [{name: 'compact_diff_lines', dismissed: false}],
    }
    ;(useRoutePayload as jest.Mock).mockReturnValue(mockPayload)
    ;(dismissUserNoticePath as jest.Mock).mockReturnValue('/dismiss-notice')

    const {result} = renderHook(() => useDismissNotice('compact_diff_lines'))

    act(() => {
      result.current.dismissNotice()
    })

    expect(verifiedFetch).toHaveBeenCalledWith('/dismiss-notice', {method: 'POST'})
  })

  it('should not call verifiedFetch if user is not logged in', () => {
    ;(isLoggedIn as jest.Mock).mockReturnValue(false)
    const mockPayload = {
      userNotices: [{name: 'compact_diff_lines', dismissed: false}],
    }
    ;(useRoutePayload as jest.Mock).mockReturnValue(mockPayload)

    const {result} = renderHook(() => useDismissNotice('compact_diff_lines'))

    act(() => {
      result.current.dismissNotice()
    })

    expect(verifiedFetch).not.toHaveBeenCalled()
  })

  it('should not call verifiedFetch if notice is already dismissed', () => {
    ;(isLoggedIn as jest.Mock).mockReturnValue(true)
    const mockPayload = {
      userNotices: [{name: 'compact_diff_lines', dismissed: true}],
    }
    ;(useRoutePayload as jest.Mock).mockReturnValue(mockPayload)

    const {result} = renderHook(() => useDismissNotice('compact_diff_lines'))

    act(() => {
      result.current.dismissNotice()
    })

    expect(verifiedFetch).not.toHaveBeenCalled()
  })
})
