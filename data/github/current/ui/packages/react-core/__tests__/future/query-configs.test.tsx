// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {http, HttpResponse} from 'msw'
import {setupServer} from 'msw/node'
import {DataRouterApplicationBuilder} from '../../future/data-router-application'
import {mainQuery} from '../../future/query-configs'
import {render} from '../../future/test-utils/Render'
import {screen} from '@testing-library/react'
import type {QueryRoute} from '../../future/query-route'

const appBuilder = DataRouterApplicationBuilder.create('react-core')

const TestComponent = () => <p>RENDERED</p>

const serverSpy = jest.fn()

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function getRoute(route: QueryRoute<string, string, string, Record<string, any>>) {
  return http.get(route.path, ({request, params}) => {
    serverSpy(request.url)
    const queries = Object.fromEntries(Object.keys(route.queries).map(queryName => [queryName, params]))
    return HttpResponse.json({payload: {[route.id]: queries}})
  })
}

const pageId = appBuilder.createQueryRouteConfig('pageId', {
  path: '/page/:id',
  queries: [mainQuery<{id: string}>()],
})
const server = setupServer(getRoute(pageId))

describe('mainQuery', () => {
  beforeAll(() => server.listen())
  afterEach(() => {
    server.resetHandlers()
    serverSpy.mockClear()
  })
  afterAll(() => server.close())

  test('mainQuery', async () => {
    const app = appBuilder.createDataRouterAppFromRoutes([pageId.toRoute({Component: TestComponent})])

    render(app, pageId.generatePath({id: '123'}))

    expect(await screen.findByText('RENDERED')).toBeInTheDocument()
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/page/123')
  })

  test('mainQuery can customize queryDeps', async () => {
    const pageIdWithParams = appBuilder.createQueryRouteConfig('pageIdWithParams', {
      path: '/param/:id',
      queries: [
        mainQuery<{id: string}>({
          queryDeps: ({pathname, searchParams}) => {
            return {
              pathname,
              searchParams: {
                foo: searchParams.get('foo'),
              },
            }
          },
        }),
      ],
    })
    server.use(getRoute(pageIdWithParams))
    const app = appBuilder.createDataRouterAppFromRoutes([
      pageId.toRoute({Component: TestComponent}),
      pageIdWithParams.toRoute({Component: TestComponent}),
    ])

    render(app, pageId.generatePath({id: '123'}, {search: 'foo=bar&not=used'}))
    expect(await screen.findByText('RENDERED')).toBeInTheDocument()
    // by default we consider ALL query params in the queryDeps
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/page/123?foo=bar&not=used')

    render(app, pageIdWithParams.generatePath({id: '123'}, {search: 'foo=bar&not=used'}))
    expect(await screen.findByText('RENDERED')).toBeInTheDocument()
    // but we can customize it to provide query params to the queryFn
    // note only the foo param is used
    expect(serverSpy).toHaveBeenCalledWith('http://localhost/param/123?foo=bar')
  })

  test('mainQuery throws on error', async () => {
    const errorRoute = appBuilder.createQueryRouteConfig('errorRoute', {
      path: '/woops',
      queries: [mainQuery<{id: string}>()],
    })
    server.use(
      http.get(errorRoute.path, () => {
        return new HttpResponse('Page not found', {status: 404})
      }),
    )
    const app = appBuilder.createDataRouterAppFromRoutes([
      errorRoute.toRoute({
        Component: TestComponent,
        ErrorBoundary: () => <p>ERROR</p>,
      }),
    ])

    render(app, errorRoute.path)

    expect(await screen.findByText('ERROR')).toBeInTheDocument()
  })
})
