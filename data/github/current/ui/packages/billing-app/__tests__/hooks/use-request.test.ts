// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {renderHook, waitFor} from '@testing-library/react'
import useRequest, {HTTPMethod} from '../../hooks/use-request'
import {USAGE_ROUTE, USAGE_REPORT_ROUTE} from '../../routes'
import {USAGE_REPORT_CUSTOM_RANGE} from '../../constants'
import type {UseRequestResponse} from '../../hooks/use-request'

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

describe('useRequest', () => {
  test('removes customer_id from req params if not cost center id', async () => {
    const response = [{id: '1'}]
    mockFetch.mockRouteOnce('/enterprises/github-inc/billing/usage?foo=1', response)

    let onStartCalled = false
    let onSuccessCalled = false
    let onErrorCalled = false
    let result: unknown = null
    renderHook(() => {
      return useRequest({
        route: USAGE_ROUTE,
        reqParams: {customer_id: '1', foo: '1'},
        onStart: () => (onStartCalled = true),
        onSuccess: r => {
          onSuccessCalled = true
          result = r.data
        },
        onError: () => (onErrorCalled = true),
      })
    })

    await waitFor(() => expect(onStartCalled).toBe(true))
    await waitFor(() => expect(onSuccessCalled).toBe(true))
    await waitFor(() => expect(onErrorCalled).toBe(false))
    await waitFor(() => expect(result).toEqual(response))
  })

  test('keeps customer_id on req params if cost center id', async () => {
    const response = [{id: '1'}]
    const costCenterId = '17c21641-6703-4f67-bad8-a73ffc536cbe'
    mockFetch.mockRouteOnce(`/enterprises/github-inc/billing/usage?customer_id=${costCenterId}&foo=1`, response)

    let onStartCalled = false
    let onSuccessCalled = false
    let onErrorCalled = false
    let result: unknown = null
    renderHook(() => {
      return useRequest({
        route: USAGE_ROUTE,
        reqParams: {customer_id: costCenterId, foo: '1'},
        onStart: () => (onStartCalled = true),
        onSuccess: r => {
          onSuccessCalled = true
          result = r.data
        },
        onError: () => (onErrorCalled = true),
      })
    })

    await waitFor(() => expect(onStartCalled).toBe(true))
    await waitFor(() => expect(onSuccessCalled).toBe(true))
    await waitFor(() => expect(onErrorCalled).toBe(false))
    await waitFor(() => expect(result).toEqual(response))
  })

  test('makes an HTTP GET request to the provided route', async () => {
    const response = [{id: '1'}]
    mockFetch.mockRouteOnce('/enterprises/github-inc/billing/usage?foo=1', response)

    let onStartCalled = false
    let onSuccessCalled = false
    let onErrorCalled = false
    let result: unknown = null
    renderHook(() => {
      return useRequest({
        route: USAGE_ROUTE,
        reqParams: {foo: '1'},
        onStart: () => (onStartCalled = true),
        onSuccess: r => {
          onSuccessCalled = true
          result = r.data
        },
        onError: () => (onErrorCalled = true),
      })
    })

    await waitFor(() => expect(onStartCalled).toBe(true))
    await waitFor(() => expect(onSuccessCalled).toBe(true))
    await waitFor(() => expect(onErrorCalled).toBe(false))
    await waitFor(() => expect(result).toEqual(response))
  })

  test('calls the onError callback when the response has an error status code', async () => {
    const response = {message: 'Something went wrong'}
    mockFetch.mockRouteOnce('/enterprises/github-inc/billing/usage?foo=1', response, {
      ok: false,
      status: 500,
    })

    let onStartCalled = false
    let onSuccessCalled = false
    let onErrorCalled = false
    let result: unknown = null
    renderHook(() => {
      return useRequest({
        route: USAGE_ROUTE,
        reqParams: {foo: '1'},
        onStart: () => (onStartCalled = true),
        onSuccess: () => (onSuccessCalled = true),
        onError: r => {
          result = (r as UseRequestResponse).data
          onErrorCalled = true
        },
      })
    })

    await waitFor(() => expect(onStartCalled).toBe(true))
    await waitFor(() => expect(onSuccessCalled).toBe(false))
    await waitFor(() => expect(onErrorCalled).toBe(true))
    await waitFor(() => expect(result).toEqual(response))
  })

  test('makes a custom usage report POST request with parameters and verifies the response', async () => {
    const startDate = new Date().toISOString().split('T')[0] || ''
    const endDate = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString().split('T')[0] || ''
    const period = USAGE_REPORT_CUSTOM_RANGE
    const response = {ok: 'true', status: 200}
    mockFetch.mockRouteOnce(
      `/enterprises/github-inc/billing/usage_report?period=${period}&start=${startDate}&end=${endDate}`,
      response,
    )

    let onStartCalled = false
    let onSuccessCalled = false
    let onErrorCalled = false
    let result: unknown = null
    renderHook(() => {
      return useRequest({
        route: USAGE_REPORT_ROUTE,
        reqParams: {
          period: String(USAGE_REPORT_CUSTOM_RANGE),
          start: startDate,
          end: endDate,
        },
        onStart: () => (onStartCalled = true),
        onSuccess: r => {
          onSuccessCalled = true
          result = r.data
        },
        onError: () => (onErrorCalled = true),
        method: HTTPMethod.GET,
      })
    })

    await waitFor(() => expect(onStartCalled).toBe(true))
    await waitFor(() => expect(onSuccessCalled).toBe(true))
    await waitFor(() => expect(onErrorCalled).toBe(false))
    await waitFor(() => expect(result).toEqual(response))
  })
})
