// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {featureFlag} from '@github-ui/feature-flags'
import {afterEach, beforeAll, beforeEach, describe, expect, it, type Mock, vi} from '@github-ui/tests'
import {http, HttpResponse, msw} from '@github-ui/tests/msw'
import {useQueryClient} from '@tanstack/react-query'
// eslint-disable-next-line testing-library/no-manual-cleanup
import {cleanup, screen} from '@testing-library/react'

import type {EmbeddedData} from '../../embedded-data-types'
import {DataRouterApplicationBuilder} from '../../future/data-router-application'
import {mainQuery} from '../../future/main-query'
import type {QueryRoute} from '../../future/query-route'
import {render} from '../../future/test-utils/Render'
import {useRouteQuery} from '../../future/use-route-query'

vi.mock('@github-ui/feature-flags')

let serverSpy: Mock
const appBuilder = DataRouterApplicationBuilder.create('react-core')

const TestComponent = () => {
  const {data, queryKey} = useRouteQuery(pageId, 'mainQuery')
  const queryClient = useQueryClient()
  const queryData = queryClient.getQueryData<{meta: {title: string}}>(queryKey)
  const title = queryData?.meta.title || 'No title provided in query meta'
  return (
    <p>
      RENDERED - {data.id} - {title}
    </p>
  )
}
const TestComponentWithParam = () => {
  const {data, queryKey} = useRouteQuery(pageIdWithParams, 'mainQuery')
  const queryClient = useQueryClient()
  const queryData = queryClient.getQueryData<{meta: {title: string}}>(queryKey)
  const title = queryData?.meta.title || ''

  return (
    <p>
      RENDERED WITH PARAMS - {data.id} - {title}
    </p>
  )
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function getRoute(route: QueryRoute<string, string, string, Record<string, any>>) {
  return http.get(route.path, ({request, params}) => {
    serverSpy(request.url, request.headers)
    return HttpResponse.json({meta: {title: 'page title'}, payload: {[route.id]: params}})
  })
}

const pageId = appBuilder.createQueryRouteConfig('pageId', {
  path: '/page/:id',
  queries: [mainQuery<{id: string}>()],
})

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

describe('mainQuery', () => {
  let baseUrl: string

  beforeAll(async () => {
    baseUrl = window.location.origin
  })
  beforeEach(() => {
    serverSpy = vi.fn()
    msw.use(getRoute(pageId))
    vi.mocked(featureFlag.isFeatureEnabled).mockReturnValue(false)
  })
  afterEach(() => {
    serverSpy.mockClear()
  })

  it('mainQuery', async () => {
    const app = appBuilder.createDataRouterAppFromRoutes([pageId.toRoute({Component: TestComponent})])

    render(app, pageId.generatePath({id: '123'}))

    expect(await screen.findByText('RENDERED - 123 - page title')).toBeInTheDocument()
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/page/123`, expect.anything())
  })

  it('mainQuery does not include X-GitHub-App-Type if feature flag is disabled', async () => {
    const app = appBuilder.createDataRouterAppFromRoutes([pageId.toRoute({Component: TestComponent})])

    render(app, pageId.generatePath({id: '123'}))

    expect(await screen.findByText('RENDERED - 123 - page title')).toBeInTheDocument()
    const headersUsedInRequest = serverSpy.mock.calls[0]?.[1] as Headers
    expect(headersUsedInRequest?.get('X-GitHub-App-Type')).toBeNull()
  })

  it('mainQuery does include X-GitHub-App-Type if feature flag is enabled', async () => {
    vi.mocked(featureFlag.isFeatureEnabled).mockReturnValue(true)

    const app = appBuilder.createDataRouterAppFromRoutes([pageId.toRoute({Component: TestComponent})])

    render(app, pageId.generatePath({id: '123'}))

    expect(await screen.findByText('RENDERED - 123 - page title')).toBeInTheDocument()
    const headersUsedInRequest = serverSpy.mock.calls[0]?.[1] as Headers
    // console.log(headersUsedInRequest)
    expect(headersUsedInRequest?.get('X-GitHub-App-Type')).toEqual('dataRouter')
  })

  it('mainQuery and embedded data', async () => {
    const app = appBuilder.createDataRouterAppFromRoutes([pageId.toRoute({Component: TestComponent})])

    const embeddedData: EmbeddedData = {
      payload: {pageId: {id: 123}},
      meta: {
        title: 'page title from embedded',
      },
      appPayload: {},
    }

    render(app, pageId.generatePath({id: '123'}), {embeddedData})

    expect(await screen.findByText('RENDERED - 123 - page title from embedded')).toBeInTheDocument()
    expect(serverSpy).not.toHaveBeenCalled()
  })

  it('mainQuery can customize queryDeps', async () => {
    msw.use(getRoute(pageIdWithParams))
    const app = appBuilder.createDataRouterAppFromRoutes([
      pageId.toRoute({Component: () => <TestComponent />}),
      pageIdWithParams.toRoute({Component: () => <TestComponentWithParam />}),
    ])

    render(app, pageId.generatePath({id: '123'}, {search: 'foo=bar&not=used'}))
    expect(await screen.findByText('RENDERED - 123 - page title')).toBeInTheDocument()
    // by default we don't consider search-params in the queryDeps
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/page/123`, expect.anything())

    cleanup()
    serverSpy.mockReset()
    expect(screen.queryByText('RENDERED - 123 - page title')).not.toBeInTheDocument()

    render(app, pageIdWithParams.generatePath({id: '123'}, {search: 'foo=bar&not=used'}))
    expect(await screen.findByText('RENDERED WITH PARAMS - 123 - page title')).toBeInTheDocument()

    // but we can customize it to provide query params to the queryFn
    // note only the foo param is used
    expect(serverSpy).toHaveBeenCalledWith(`${baseUrl}/param/123?foo=bar`, expect.anything())
  })

  it('mainQuery throws on error', async () => {
    const errorRoute = appBuilder.createQueryRouteConfig('errorRoute', {
      path: '/woops',
      queries: [mainQuery<{id: string}>()],
    })
    msw.use(
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
