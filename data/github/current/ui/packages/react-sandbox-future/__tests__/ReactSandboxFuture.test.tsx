// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'
import {DEFAULT_STALE_TIME_FOR_NAVIGATION} from '@github-ui/react-core/future/query-route'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {SoftNavPayloadEvent} from '@github-ui/soft-nav/events'
import {succeedSoftNav} from '@github-ui/soft-nav/state'
import {act, type ByRoleOptions, screen, within} from '@testing-library/react'
import {http, HttpResponse} from 'msw'

import {reactSandboxFutureApp} from '../react-sandbox-future'
import {setupServer} from './utils/mock-server/server'

jest.mock('@github-ui/failbot', () => ({
  reportError: jest.fn(),
}))

jest.mock('@github-ui/soft-nav/state', () => {
  const actual = jest.requireActual('@github-ui/soft-nav/state')
  return {
    ...actual,
    succeedSoftNav: jest.fn(actual.succeedSoftNav),
  }
})

const mockedSucceedSoftNav = jest.mocked(succeedSoftNav)

const mockReportError = jest.mocked(reportError)
const {server} = setupServer()

function getReactNavigationLinkByName(name: ByRoleOptions['name']) {
  return within(screen.getByRole('list', {name: 'React navigation'})).getByRole('link', {name})
}

describe('ReactSandboxFutureApp', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  test('can test the registered app', async () => {
    render(reactSandboxFutureApp, '/_react_sandbox_future')

    expect(await screen.findByText(/ReactSandboxFutureIndex/)).toBeInTheDocument()
  })

  test('can test the registered app with route /1, when passed an array of routes', async () => {
    const {user, router} = render(reactSandboxFutureApp, ['/_react_sandbox_future/1'])

    expect(await screen.findByText(/ReactSandboxFutureId: id=1/)).toBeInTheDocument()
    expect(screen.queryByText(/ReactSandboxFutureId: id=2/)).not.toBeInTheDocument()
    expect(router.state.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/1',
      }),
    )

    await user.click(getReactNavigationLinkByName(/\/_react_sandbox_future\/2/))

    expect(await screen.findByText(/ReactSandboxFutureId: id=2/)).toBeInTheDocument()
    expect(screen.queryByText(/ReactSandboxFutureId: id=1/)).not.toBeInTheDocument()
    expect(router.state.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/2',
      }),
    )
  })

  test('can test the registered app with route /2, when passed a routerOptions object', async () => {
    const {user, router} = render(reactSandboxFutureApp, {
      initialEntries: ['/_react_sandbox_future/2'],
      initialIndex: 0,
    })

    expect(await screen.findByText(/ReactSandboxFutureId: id=2/)).toBeInTheDocument()
    expect(screen.queryByText(/ReactSandboxFutureId: id=1/)).not.toBeInTheDocument()
    expect(router.state.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/2',
      }),
    )

    await user.click(getReactNavigationLinkByName(/\/_react_sandbox_future\/1/))

    expect(await screen.findByText(/ReactSandboxFutureId: id=1/)).toBeInTheDocument()
    expect(screen.queryByText(/ReactSandboxFutureId: id=2/)).not.toBeInTheDocument()
    expect(router.state.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/1',
      }),
    )
  })

  test('shows error message when server returns non-2XX status in response', async () => {
    const {user, router} = render(reactSandboxFutureApp, ['/_react_sandbox_future/1'])

    expect(await screen.findByText(/ReactSandboxFutureId: id=1/)).toBeInTheDocument()
    expect(screen.queryByText(/Unable to load page./)).not.toBeInTheDocument()
    expect(screen.queryByText(/Status: 404/)).not.toBeInTheDocument()
    expect(router.state.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/1',
      }),
    )

    await user.click(getReactNavigationLinkByName(/404 Error/))

    expect(await screen.findByText(/Unable to load page./)).toBeInTheDocument()
    expect(await screen.findByText(/Status: 404/)).toBeInTheDocument()
    expect(screen.queryByText(/ReactSandboxFutureId: id=1/)).not.toBeInTheDocument()
    expect(router.state.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/3',
      }),
    )

    // Note: When this error occurs, the ErrorBoundary component will call reportError
    // This is handled by the ErrorBoundary's componentDidCatch method which calls
    // either the provided onError function or the default error handler, both of which
    // call reportError with the ResponseError containing status 500
    expect(mockReportError).toHaveBeenCalledTimes(1)
    expect(mockReportError).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'ResponseError',
        response: expect.objectContaining({status: 404}),
      }),
      {critical: true, reactAppName: 'react-sandbox-future'},
    )
  })

  describe('error handling', () => {
    test('shows error message when mainQuery returns 500 server error', async () => {
      // Mock server to return 500 error for layout route
      server.use(
        http.get('/_react_sandbox_future/_layout', () => {
          return new HttpResponse(null, {status: 500})
        }),
      )

      const {router} = render(reactSandboxFutureApp, '/_react_sandbox_future')

      // Should show error message for failing blocking query
      expect(await screen.findByText(/Unable to load page./)).toBeInTheDocument()
      expect(await screen.findByText(/Status: 500/)).toBeInTheDocument()
      expect(screen.queryByText(/ReactSandboxFutureIndex/)).not.toBeInTheDocument()
      expect(router.state.location).toEqual(
        expect.objectContaining({
          pathname: '/_react_sandbox_future',
        }),
      )

      // Note: When this error occurs, the ErrorBoundary component will call reportError
      // This is handled by the ErrorBoundary's componentDidCatch method which calls
      // either the provided onError function or the default error handler, both of which
      // call reportError with the ResponseError containing status 500
      expect(mockReportError).toHaveBeenCalledTimes(1)
      expect(mockReportError).toHaveBeenCalledWith(
        expect.objectContaining({name: 'ResponseError', response: expect.objectContaining({status: 500})}),
        {critical: true, reactAppName: 'react-sandbox-future'},
      )
      expect(mockedSucceedSoftNav).toHaveBeenCalledTimes(1)
    })

    test('shows error message when soft navigating to a route that returns a 500 error', async () => {
      // Start with a successful initial page load
      const {user, router} = render(reactSandboxFutureApp, '/_react_sandbox_future/1')

      // Verify initial page loaded correctly
      expect(await screen.findByText(/ReactSandboxFutureId: id=1/)).toBeInTheDocument()
      expect(screen.queryByText(/Unable to load page./)).not.toBeInTheDocument()
      expect(mockedSucceedSoftNav).toHaveBeenCalledTimes(1)
      // Now mock the server to return 500 error for route 2
      server.use(
        http.get('/_react_sandbox_future/2', () => {
          return new HttpResponse(null, {status: 500})
        }),
      )

      // Navigate to route 2, which should now fail
      await user.click(getReactNavigationLinkByName(/\/_react_sandbox_future\/2/))

      // Should show error message for the failing route
      expect(await screen.findByText(/Unable to load page./)).toBeInTheDocument()
      expect(await screen.findByText(/Status: 500/)).toBeInTheDocument()
      expect(screen.queryByText(/ReactSandboxFutureId: id=1/)).not.toBeInTheDocument()
      expect(screen.queryByText(/ReactSandboxFutureId: id=2/)).not.toBeInTheDocument()
      expect(router.state.location).toEqual(
        expect.objectContaining({
          pathname: '/_react_sandbox_future/2',
        }),
      )

      // Verify reportError was called with a ResponseError
      expect(mockReportError).toHaveBeenCalledTimes(1)
      const errorArg = mockReportError.mock.calls[0]![0]
      expect(errorArg).toMatchObject({name: 'ResponseError', response: expect.objectContaining({status: 500})})
      expect(mockedSucceedSoftNav).toHaveBeenCalledTimes(2)
    })
  })

  describe('Embedded data', () => {
    test("will fetch when there's no embedded data", async () => {
      const requestSpy = jest.fn()
      server.use(
        http.get('*', ({request}) => {
          requestSpy(request.url)
        }),
      )
      render(reactSandboxFutureApp, '/_react_sandbox_future/123')

      expect(await screen.findByText(/ReactSandboxFutureId/)).toBeInTheDocument()
      expect(screen.queryByTestId('reactSandboxFutureLayoutRoute-mainQuery-data')).toHaveTextContent(
        /SERVER DATA – layoutRoute/,
      )
      // make sure we are just getting the data for the route/query and not the entire response
      expect(screen.queryByTestId('reactSandboxFutureLayoutRoute-mainQuery-data')).not.toHaveTextContent(/mainQuery/)
      // we expect a request for the id-route and the layout route
      expect(requestSpy).toHaveBeenCalledTimes(3)
      expect(requestSpy).toHaveBeenNthCalledWith(1, expect.stringMatching(/\/_react_sandbox_future\/_layout$/))
      expect(requestSpy).toHaveBeenNthCalledWith(2, expect.stringMatching(/\/_react_sandbox_future\/123$/))
      expect(requestSpy).toHaveBeenNthCalledWith(3, expect.stringMatching(/\/_react_sandbox_future\/123\/deferred$/))
    })

    test('will load from embedded data and will not fetch', async () => {
      const requestSpy = jest.fn()
      server.use(
        http.get('*', ({request}) => {
          requestSpy(request.url)
        }),
      )
      render(reactSandboxFutureApp, '/_react_sandbox_future/123', {
        embeddedData: {
          payload: {
            reactSandboxFutureLayoutRoute: {
              someField: 'EMBEDDED DATA – layoutRoute',
              tabCounts: {'1': 1, '2': 2, '3': 3},
            },
          },
        },
      })

      expect(await screen.findByText(/ReactSandboxFutureId/)).toBeInTheDocument()
      expect(await screen.findByTestId('reactSandboxFutureLayoutRoute-mainQuery-data')).toHaveTextContent(
        /EMBEDDED DATA – layoutRoute/,
      )
      // make sure we are just getting the data for the route/query and not the entire response
      expect(screen.queryByTestId('reactSandboxFutureLayoutRoute-mainQuery-data')).not.toHaveTextContent(/mainQuery/)
      // we expect a request for the id-route BUT NOT the layout route
      expect(requestSpy).toHaveBeenCalledTimes(2)
      expect(requestSpy).toHaveBeenNthCalledWith(1, expect.stringMatching(/\/_react_sandbox_future\/123$/))
      expect(requestSpy).toHaveBeenNthCalledWith(2, expect.stringMatching(/\/_react_sandbox_future\/123\/deferred$/))
    })
  })

  test('navigating to same route does not refetch parent data', async () => {
    const urlHash: Record<string, number> = {}
    const requestSpy = jest.fn()
    server.use(
      http.get('*', ({request}) => {
        requestSpy(request.url)
        if (urlHash.hasOwnProperty(request.url)) {
          urlHash[request.url] = (urlHash[request.url] ?? 0) + 1
        } else {
          urlHash[request.url] = 1
        }
      }),
    )
    const {user} = render(reactSandboxFutureApp, '/_react_sandbox_future/1', {
      embeddedData: {
        payload: {
          reactSandboxFutureLayoutRoute: {
            someField: 'EMBEDDED DATA – layoutRouteP',
            tabCounts: {'1': 1, '2': 2, '3': 3},
          },
        },
      },
    })
    expect(await screen.findByText(/ReactSandboxFutureId/)).toBeInTheDocument()
    expect(await screen.findByTestId('reactSandboxFutureLayoutRoute-mainQuery-data')).toHaveTextContent(
      /EMBEDDED DATA – layoutRouteP/,
    )
    // make sure we are just getting the data for the route/query and not the entire response
    expect(screen.queryByTestId('reactSandboxFutureLayoutRoute-mainQuery-data')).not.toHaveTextContent(/mainQuery/)
    // we expect a request for the id-route BUT NOT the layout route
    expect(requestSpy).toHaveBeenCalledTimes(2)
    expect(requestSpy).toHaveBeenCalledWith('http://localhost/_react_sandbox_future/1')
    expect(requestSpy).toHaveBeenCalledWith('http://localhost/_react_sandbox_future/1/deferred')
    expect(urlHash['http://localhost/_react_sandbox_future/1']).toBe(1)
    expect(urlHash['http://localhost/_react_sandbox_future/1/deferred']).toBe(1)

    jest.useFakeTimers()
    act(() => jest.advanceTimersByTime(DEFAULT_STALE_TIME_FOR_NAVIGATION + 50)) // want to advance timer to expire tsq cache
    await user.click(getReactNavigationLinkByName(/\/_react_sandbox_future\/1/))
    jest.useRealTimers() // if fake timers are used for entire test we get act warnings

    expect(await screen.findAllByText(/someDeferredField/)).toBeTruthy()
    expect(await screen.findByText(/ReactSandboxFutureId: id=1/)).toBeInTheDocument()
    expect(requestSpy).toHaveBeenCalledTimes(4)
  })

  describe('navigating sends custom soft-nav event', () => {
    let dispatchEventSpy: jest.SpyInstance<boolean, Parameters<typeof document.dispatchEvent>>

    function getDispatchedSoftnavPayloadEvents(spy: typeof dispatchEventSpy) {
      return spy.mock.calls.map(([call]) => call).filter(call => call instanceof SoftNavPayloadEvent)
    }

    beforeEach(() => {
      dispatchEventSpy = jest.spyOn(document, 'dispatchEvent')
    })
    afterEach(() => {
      dispatchEventSpy.mockRestore()
    })
    test('hard nav sends event', async () => {
      render(reactSandboxFutureApp, '/_react_sandbox_future')
      expect(await screen.findByText(/ReactSandboxFutureIndex/)).toBeInTheDocument()
      const softNavPayloadEvents = getDispatchedSoftnavPayloadEvents(dispatchEventSpy)
      expect(softNavPayloadEvents).toHaveLength(1)
    })
    test('soft nav sends event', async () => {
      const {user} = render(reactSandboxFutureApp, '/_react_sandbox_future')
      expect(await screen.findByText(/ReactSandboxFutureIndex/)).toBeInTheDocument()
      const softNavPayloadEvents1 = getDispatchedSoftnavPayloadEvents(dispatchEventSpy)
      expect(softNavPayloadEvents1).toHaveLength(1)

      await user.click(getReactNavigationLinkByName(/\/_react_sandbox_future\/1/))
      expect(await screen.findByText(/ReactSandboxFutureId: id=1/)).toBeInTheDocument()

      const softNavPayloadEvents2 = getDispatchedSoftnavPayloadEvents(dispatchEventSpy)
      expect(softNavPayloadEvents2).toHaveLength(2)
      expect(softNavPayloadEvents2[0]?.payload).toBeDefined()
      expect(softNavPayloadEvents2[1]?.payload).toBeDefined()
      expect(softNavPayloadEvents2[0]?.payload).not.toEqual(softNavPayloadEvents1[1]?.payload)
    })
  })

  describe('navigating updates the document title', () => {
    test('soft nav updates the title (index and id page)', async () => {
      const {user} = render(reactSandboxFutureApp, '/_react_sandbox_future/1')
      expect(await screen.findByText(/ReactSandboxFutureId: id=1/)).toBeInTheDocument()
      expect(document.title).toBe('React Sandbox ID 1')

      await user.click(getReactNavigationLinkByName(/\/_react_sandbox_future\/2/))
      expect(await screen.findByText(/ReactSandboxFutureId: id=2/)).toBeInTheDocument()
      expect(document.title).toBe('React Sandbox ID 2')

      await user.click(getReactNavigationLinkByName(/\/_react_sandbox_future$/))
      expect(await screen.findByText(/ReactSandboxFutureIndex/)).toBeInTheDocument()
      expect(document.title).toBe('React Sandbox Index')
    })
  })

  test("navigating outside of the app doesn't flash the error boundary", async () => {
    const warnSpy = jest.spyOn(console, 'warn').mockImplementation()
    const {router} = render(reactSandboxFutureApp, ['/_some_route_outside_the_app', '/_react_sandbox_future'])
    expect(await screen.findByText(/ReactSandboxFutureIndex/)).toBeInTheDocument()

    await act(() => router.navigate(-1))
    expect(screen.queryByText(/Unable to load page./)).not.toBeInTheDocument()
    expect(warnSpy).toHaveBeenNthCalledWith(1, 'No routes matched location "/_some_route_outside_the_app" ')
  })
})
