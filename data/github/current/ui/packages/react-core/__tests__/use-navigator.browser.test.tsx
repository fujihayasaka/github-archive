// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {describe, expect, it, vi} from '@github-ui/tests'
import {http, HttpResponse, msw} from '@github-ui/tests/msw'
import {Action} from '@remix-run/router'
import {act, renderHook, waitFor} from '@testing-library/react'

import {jsonRoute} from '../JsonRoute'
import {useNavigator} from '../use-navigator'

function buildLocation(pathname: string, key: string) {
  return {pathname, search: '', hash: '', state: null, key}
}

const blueHomeInitData = {
  initialLocation: buildLocation('/home', 'h1'),
  appName: 'my-app',
  embeddedData: {payload: {color: 'blue'}, appPayload: {helpUrl: 'https://help.github.com'}},
  routes: [
    jsonRoute({path: '/home', Component: () => null}),
    jsonRoute({path: '/about', Component: () => null}),
    jsonRoute({path: '/will-fail', Component: () => null}),
    jsonRoute({path: '/pass-error', Component: () => null, shouldNavigateOnError: true}),
  ],
}

describe('useNavigator', () => {
  it('gets initial payload', () => {
    const {result} = renderHook(() => useNavigator(blueHomeInitData))

    const [{appPayload, location, routeStateMap}] = result.current
    expect(appPayload).toEqual({helpUrl: 'https://help.github.com'})
    expect(location.pathname).toBe('/home')
    expect((routeStateMap['h1']!.data as {payload: unknown}).payload).toEqual({color: 'blue'})
  })

  it('fetches the new page payload on navigation', async () => {
    const {result} = renderHook(() => useNavigator(blueHomeInitData))
    const [{location}, {handleHistoryUpdate}] = result.current
    expect(location.pathname).toBe('/home')

    msw.use(
      http.get('/about', () => {
        return HttpResponse.json({payload: {color: 'red'}})
      }),
    )

    // We need 2 steps to simulate navigation: update window.location, and then trigger handleHistoryUpdate
    history.pushState({}, '', '/about')
    await act(() => handleHistoryUpdate({location: buildLocation('/about', 'a1'), action: Action.Push, delta: 1}))

    const [{location: loadingLocation}] = result.current
    expect(loadingLocation.pathname).toBe('/home')

    await waitFor(() => {
      const [{isLoading}] = result.current
      expect(isLoading).toBe(false)
    })

    const [{location: newLocation, routeStateMap}] = result.current
    expect(newLocation.pathname).toBe('/about')
    expect((routeStateMap['a1']!.data as {payload: unknown}).payload).toEqual({color: 'red'})
  })

  it('reports error when the initial route is not present in the React app', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})

    const wrongRouteInitData = {...blueHomeInitData, initialLocation: buildLocation('/unknown', 'w1')}
    expect(() => renderHook(() => useNavigator(wrongRouteInitData))).toThrow(
      'No route found for initial location: /unknown in [/home, /about, /will-fail, /pass-error]',
    )
  })

  it('reports error when it fails navigating to a route', async () => {
    const {result} = renderHook(() => useNavigator(blueHomeInitData))
    const [{location}, {handleHistoryUpdate}] = result.current
    expect(location.pathname).toBe('/home')

    msw.use(
      http.get('/will-fail', () => {
        return new HttpResponse('Not found', {status: 404})
      }),
    )

    history.pushState({}, '', '/will-fail')
    act(() => handleHistoryUpdate({location: buildLocation('/will-fail', 'w1'), action: Action.Push, delta: 1}))
    await waitFor(() => {
      const [{isLoading}] = result.current
      expect(isLoading).toBe(false)
    })

    const [{location: newLocation, error, navigateOnError}] = result.current
    expect(newLocation.pathname).toBe('/will-fail')
    expect(error).toEqual({type: 'httpError', httpStatus: 404})
    expect(navigateOnError).toBe(false)
  })

  it('reports error when it fails navigating to a route with navigateOnError', async () => {
    const {result} = renderHook(() => useNavigator(blueHomeInitData))
    const [{location}, {handleHistoryUpdate}] = result.current
    expect(location.pathname).toBe('/home')

    msw.use(
      http.get('/pass-error', () => {
        return new HttpResponse('Not found', {status: 404})
      }),
    )

    history.pushState({}, '', 'pass-error')
    // react-router matchPath requires an initial slash in the new location to match
    act(() => handleHistoryUpdate({location: buildLocation('/pass-error', 'p1'), action: Action.Push, delta: 1}))
    await waitFor(() => {
      const [{isLoading}] = result.current
      expect(isLoading).toBe(false)
    })

    const [{location: newLocation, error, navigateOnError}] = result.current
    expect(newLocation.pathname).toBe('/pass-error')
    expect(error).toEqual({type: 'httpError', httpStatus: 404})
    expect(navigateOnError).toBe(true)
  })

  it('reports error when the fetch response is invalid', async () => {
    const {result} = renderHook(() => useNavigator(blueHomeInitData))
    const [{location}, {handleHistoryUpdate}] = result.current
    expect(location.pathname).toBe('/home')

    msw.use(
      http.get('/pass-error', () => {
        return new HttpResponse('badResponseError', {
          status: 200,
          headers: {'Content-Type': 'application/json'},
        })
      }),
    )
    history.pushState({}, '', 'pass-error')
    act(() => handleHistoryUpdate({location: buildLocation('/pass-error', 'p1'), action: Action.Push, delta: 1}))
    await waitFor(() => {
      const [{isLoading}] = result.current
      expect(isLoading).toBe(false)
    })

    const [{location: newLocation, error, navigateOnError}] = result.current
    expect(newLocation.pathname).toBe('/pass-error')
    expect(error).toEqual({type: 'badResponseError'})
    expect(navigateOnError).toBe(true)
  })

  it('reports error when the fetch fails (network down)', async () => {
    const {result} = renderHook(() => useNavigator(blueHomeInitData))
    const [{location}, {handleHistoryUpdate}] = result.current
    expect(location.pathname).toBe('/home')

    msw.use(
      http.get('/pass-error', () => {
        return HttpResponse.error()
      }),
    )

    history.pushState({}, '', 'pass-error')
    act(() => handleHistoryUpdate({location: buildLocation('/pass-error', 'p1'), action: Action.Push, delta: 1}))
    await waitFor(() => {
      const [{isLoading}] = result.current
      expect(isLoading).toBe(false)
    })

    const [{location: newLocation, error, navigateOnError}] = result.current
    expect(newLocation.pathname).toBe('/pass-error')
    expect(error).toEqual({type: 'fetchError'})
    expect(navigateOnError).toBe(true)
  })
})
