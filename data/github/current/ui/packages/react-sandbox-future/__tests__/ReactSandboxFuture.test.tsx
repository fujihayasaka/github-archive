import {act, screen, within, type ByRoleOptions} from '@testing-library/react'
import {render, RouteContext} from '@github-ui/react-core/future/test-utils/render'
import {SoftNavPayloadEvent} from '@github-ui/soft-nav/events'
import {http, HttpResponse} from 'msw'
import {setupServer} from 'msw/node'
import {reactSandboxFutureApp} from '../react-sandbox-future'
import {
  getReactSandboxDeferredPayload,
  getReactSandboxFutureIdRoutePayload,
  getReactSandboxFutureIndexRoutePayload,
} from '../test-utils/mock-data'

const serverSpy = jest.fn()

const server = setupServer(
  http.get('/_react_sandbox_future', () => {
    const response = getReactSandboxFutureIndexRoutePayload()
    serverSpy(response)
    return HttpResponse.json(response)
  }),
  http.get('/_react_sandbox_future/:id/deferred', ({params}) => {
    const {id} = params
    const response = getReactSandboxDeferredPayload(id as string)
    return HttpResponse.json(response)
  }),
  http.get('/_react_sandbox_future/:id', ({params}) => {
    const {id} = params
    const response = getReactSandboxFutureIdRoutePayload(id as string)
    serverSpy(response)
    if (id === '3') {
      return new HttpResponse('Page not found', {status: 404})
    }
    return HttpResponse.json(response)
  }),
)

function getReactNavigationLinkByName(name: ByRoleOptions['name']) {
  return within(screen.getByRole('list', {name: 'React navigation'})).getByRole('link', {name})
}

describe('ReactSandboxFutureApp', () => {
  beforeAll(() => server.listen())
  afterEach(() => {
    server.resetHandlers()
    serverSpy.mockClear()
  })
  afterAll(() => server.close())

  test('can test the registered app', async () => {
    await render(reactSandboxFutureApp, '/_react_sandbox_future')

    expect(await screen.findByText(/ReactSandboxFutureIndex/)).toBeInTheDocument()
  })

  test('can test the registered app with route /1, when passed an array of routes', async () => {
    const {user} = await render(reactSandboxFutureApp, ['/_react_sandbox_future/1'])

    expect(await screen.findByText(/ReactSandboxFutureId: id=1/)).toBeInTheDocument()
    expect(screen.queryByText(/ReactSandboxFutureId: id=2/)).not.toBeInTheDocument()
    expect(RouteContext.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/1',
      }),
    )

    await user.click(getReactNavigationLinkByName(/\/_react_sandbox_future\/2/))

    expect(await screen.findByText(/ReactSandboxFutureId: id=2/)).toBeInTheDocument()
    expect(screen.queryByText(/ReactSandboxFutureId: id=1/)).not.toBeInTheDocument()
    expect(RouteContext.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/2',
      }),
    )
  })

  test('can test the registered app with route /2, when passed a routerOptions object', async () => {
    const {user} = await render(reactSandboxFutureApp, {
      initialEntries: ['/_react_sandbox_future/2'],
      initialIndex: 0,
    })

    expect(await screen.findByText(/ReactSandboxFutureId: id=2/)).toBeInTheDocument()
    expect(screen.queryByText(/ReactSandboxFutureId: id=1/)).not.toBeInTheDocument()
    expect(RouteContext.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/2',
      }),
    )

    await user.click(getReactNavigationLinkByName(/\/_react_sandbox_future\/1/))

    expect(await screen.findByText(/ReactSandboxFutureId: id=1/)).toBeInTheDocument()
    expect(screen.queryByText(/ReactSandboxFutureId: id=2/)).not.toBeInTheDocument()
    expect(RouteContext.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/1',
      }),
    )
  })

  test('shows error message when server returns non-2XX status in response', async () => {
    const {user} = await render(reactSandboxFutureApp, ['/_react_sandbox_future/1'])

    expect(await screen.findByText(/ReactSandboxFutureId: id=1/)).toBeInTheDocument()
    expect(screen.queryByText(/Unable to load page./)).not.toBeInTheDocument()
    expect(screen.queryByText(/Status: 404/)).not.toBeInTheDocument()
    expect(RouteContext.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/1',
      }),
    )

    await user.click(getReactNavigationLinkByName(/404 Error/))

    expect(await screen.findByText(/Unable to load page./)).toBeInTheDocument()
    expect(await screen.findByText(/Status: 404/)).toBeInTheDocument()
    expect(screen.queryByText(/ReactSandboxFutureId: id=1/)).not.toBeInTheDocument()
    expect(RouteContext.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/3',
      }),
    )
  })

  describe('Embedded data', () => {
    test("will fetch when there's no embedded data", async () => {
      await render(reactSandboxFutureApp, '/_react_sandbox_future/123')

      expect(await screen.findByText(/ReactSandboxFutureId/)).toBeInTheDocument()
      expect(screen.queryByTestId('reactSandboxFutureLayoutRoute-mainQuery-data')).toHaveTextContent(
        /SERVER DATA – layoutRoute/,
      )
      // make sure we are just getting the data for the route/query and not the entire response
      expect(screen.queryByTestId('reactSandboxFutureLayoutRoute-mainQuery-data')).not.toHaveTextContent(/mainQuery/)
      // we expect a request for the id-route and the layout route
      expect(serverSpy).toHaveBeenCalledTimes(2)
      expect(serverSpy).toHaveBeenNthCalledWith(1, getReactSandboxFutureIndexRoutePayload())
      expect(serverSpy).toHaveBeenNthCalledWith(2, getReactSandboxFutureIdRoutePayload('123'))
    })

    test('will load from embedded data and will not fetch', async () => {
      await render(reactSandboxFutureApp, '/_react_sandbox_future/123', {
        embeddedData: {
          payload: {
            reactSandboxFutureLayoutRoute: {
              mainQuery: {someField: 'EMBEDDED DATA – layoutRoute', tabCounts: {'1': 1, '2': 2, '3': 3}},
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
      expect(serverSpy).toHaveBeenCalledTimes(1)
      expect(serverSpy).toHaveBeenCalledWith(getReactSandboxFutureIdRoutePayload('123'))
    })
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
      await render(reactSandboxFutureApp, '/_react_sandbox_future')
      expect(await screen.findByText(/ReactSandboxFutureIndex/)).toBeInTheDocument()
      const softNavPayloadEvents = getDispatchedSoftnavPayloadEvents(dispatchEventSpy)
      expect(softNavPayloadEvents).toHaveLength(1)
    })
    test('soft nav sends event', async () => {
      const {user} = await render(reactSandboxFutureApp, '/_react_sandbox_future')
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
      const {user} = await render(reactSandboxFutureApp, '/_react_sandbox_future/1')
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
    const {router} = await render(reactSandboxFutureApp, ['/_some_route_outside_the_app', '/_react_sandbox_future'])
    expect(await screen.findByText(/ReactSandboxFutureIndex/)).toBeInTheDocument()

    await act(() => router.navigate(-1))
    expect(screen.queryByText(/Unable to load page./)).not.toBeInTheDocument()
    expect(warnSpy).toHaveBeenNthCalledWith(1, 'No routes matched location "/_some_route_outside_the_app" ')
  })
})
