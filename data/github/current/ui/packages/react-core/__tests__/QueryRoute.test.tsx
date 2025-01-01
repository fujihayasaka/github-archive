import {startSoftNav} from '@github-ui/soft-nav/state'
import {dehydrate} from '@tanstack/react-query'
import {act, screen, waitFor} from '@testing-library/react'
import {Profiler} from 'react'
import {Link, Outlet} from 'react-router-dom'
import {DataRouterApplicationBuilder, InvalidIdentifierError} from '../future/data-router-application'
import {QueryRouteQueryType} from '../future/data-router-types'
import {render} from '../future/test-utils/Render'
import {useRouteQuery} from '../future/use-route-query'
import {mainQuery} from '../future/query-configs'
import {getQueryClient} from '../query-client'
import {makeQueryKey} from '../query-key'
import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'
import {DEFAULT_STALE_TIME_FOR_NAVIGATION} from '../future/query-route'

const appBuilder = DataRouterApplicationBuilder.create('react-core')

jest.mock('@github-ui/soft-nav/state', () => {
  const actual = jest.requireActual('@github-ui/soft-nav/state')
  return {
    ...actual,
    startSoftNav: jest.fn().mockImplementation(actual.startSoftNav),
  }
})

const mockedStartSoftNav = jest.mocked(startSoftNav)

const TestComponent = () => <p>Bar</p>
const TestOutletComponent = () => (
  <div>
    <Outlet />
  </div>
)
const originalWindow = {...global.window}

const server = setupServer()

describe('queryRoute', () => {
  beforeAll(() => {
    server.listen()
  })
  beforeEach(() => {
    mockedStartSoftNav.mockReset()
  })
  afterEach(() => {
    global.window = originalWindow
    server.resetHandlers()
  })
  afterAll(() => {
    server.close()
  })
  test('correctly passes urls for nested routes', async () => {
    const queryDepsSpy = jest.fn()
    const queryFnSpy = jest.fn()

    const app = appBuilder.createDataRouterAppFromRoutes([
      appBuilder
        .createQueryRouteConfig('page', {
          path: '/page',
          queries: [
            {
              queryName: 'payload',
              queryDeps: (...args) => {
                queryDepsSpy(args)
                return {url: args[0].pathname}
              },
              queryFn: (...args) => {
                queryFnSpy(args)
                return 'fake data'
              },
              type: QueryRouteQueryType.Blocking,
            },
          ],
        })
        .toRoute({
          Component: TestOutletComponent,
          children: [
            appBuilder
              .createQueryRouteConfig('pageId', {
                path: '/page/:id',
                queries: [
                  {
                    queryName: 'payload',
                    queryDeps: (...args) => {
                      queryDepsSpy(args)
                      return {url: args[0].pathname}
                    },
                    queryFn: (...args) => {
                      queryFnSpy(args)
                      return 'fake data'
                    },
                    type: QueryRouteQueryType.Blocking,
                  },
                ],
              })
              .toRoute({
                Component: TestComponent,
              }),
          ],
        }),
    ])
    render(app, '/page/123')
    await waitFor(() => expect(queryDepsSpy).toHaveBeenCalledTimes(2))

    expect(queryDepsSpy).toHaveBeenNthCalledWith(1, [
      {
        params: {id: '123'},
        pathname: '/page',
        searchParams: new URLSearchParams(),
      },
    ])
    expect(queryDepsSpy).toHaveBeenNthCalledWith(2, [
      {
        params: {id: '123'},
        pathname: '/page/123',
        searchParams: new URLSearchParams(),
      },
    ])

    expect(queryFnSpy).toHaveBeenCalledTimes(2)
    expect(queryFnSpy).toHaveBeenNthCalledWith(1, [
      {appName: 'react-core', routeId: 'page', routePath: '/page', queryName: 'payload', queryDeps: {url: '/page'}},
      {meta: undefined, signal: new AbortController().signal},
    ])
    expect(queryFnSpy).toHaveBeenNthCalledWith(2, [
      {
        appName: 'react-core',
        routeId: 'pageId',
        routePath: '/page/:id',
        queryName: 'payload',
        queryDeps: {url: '/page/123'},
      },
      {meta: undefined, signal: new AbortController().signal},
    ])
  })

  test('correctly passes search params', async () => {
    const queryDepsSpy = jest.fn()
    const queryFnSpy = jest.fn()

    const testPageRoute = appBuilder.createQueryRouteConfig('testPageRoute', {
      path: '/page',
      queries: [
        {
          queryName: 'payload',
          queryDeps: (...args) => {
            queryDepsSpy(args)
            return {url: args[0].pathname}
          },
          queryFn: (...args) => {
            queryFnSpy(args)
            return 'fake data'
          },
          type: QueryRouteQueryType.Blocking,
        },
      ],
    })

    const testPageIdRoute = appBuilder.createQueryRouteConfig('testPageIdRoute', {
      path: '/page/:id',
      queries: [
        {
          queryName: 'payload',
          queryDeps: (...args) => {
            queryDepsSpy(args)
            return {url: args[0].pathname}
          },
          queryFn: (...args) => {
            queryFnSpy(args)
            return 'fake data'
          },
          type: QueryRouteQueryType.Blocking,
        },
      ],
    })
    const app = appBuilder.createDataRouterAppFromRoutes([
      testPageRoute.toRoute({
        Component: TestOutletComponent,
        children: [testPageIdRoute.toRoute({Component: TestComponent})],
      }),
    ])

    render(app, '/page/123?foo=bar')
    await waitFor(() => expect(queryDepsSpy).toHaveBeenCalledTimes(2))

    expect(queryDepsSpy).toHaveBeenNthCalledWith(1, [
      {
        params: {id: '123'},
        pathname: '/page',
        searchParams: new URLSearchParams({foo: 'bar'}),
      },
    ])
    expect(queryDepsSpy).toHaveBeenNthCalledWith(2, [
      {
        params: {id: '123'},
        pathname: '/page/123',
        searchParams: new URLSearchParams({foo: 'bar'}),
      },
    ])

    expect(queryFnSpy).toHaveBeenCalledTimes(2)
    expect(queryFnSpy).toHaveBeenNthCalledWith(1, [
      {
        appName: 'react-core',
        routeId: 'testPageRoute',
        routePath: '/page',
        queryName: 'payload',
        queryDeps: {url: '/page'},
      },
      {meta: undefined, signal: new AbortController().signal},
    ])
    expect(queryFnSpy).toHaveBeenNthCalledWith(2, [
      {
        appName: 'react-core',
        routeId: 'testPageIdRoute',
        routePath: '/page/:id',
        queryName: 'payload',
        queryDeps: {url: '/page/123'},
      },
      {meta: undefined, signal: new AbortController().signal},
    ])
  })

  test('allows creating an index route', async () => {
    const routeConfig = appBuilder.createQueryRouteConfig('routeConfig', {
      path: '/foo',
      index: true,
    })
    expect(routeConfig).toEqual({
      id: 'routeConfig',
      index: true,
      generatePath: expect.any(Function),
      queries: {},
      toRoute: expect.any(Function),
      path: '/foo',
      isSameRoute: expect.any(Function),
    })

    const route = routeConfig.toRoute({})
    if (typeof route.loader !== 'function') throw new Error('loader must be a function')
    expect(await route.loader({request: new Request(''), params: {}})).toEqual({
      route: routeConfig,
      queries: {},
    })
    expect(mockedStartSoftNav).toHaveBeenCalledTimes(1)
    expect(dehydrate(getQueryClient())).toEqual({
      queries: [],
      mutations: [],
    })
  })

  test('allows creating a non-index route', async () => {
    const fooRoute = appBuilder.createQueryRouteConfig('fooRoute', {
      path: '/foo',
    })
    expect(fooRoute).toEqual({
      generatePath: expect.any(Function),
      path: '/foo',
      id: 'fooRoute',
      isSameRoute: expect.any(Function),
      index: false,
      queries: {},
      toRoute: expect.any(Function),
    })

    const route = fooRoute.toRoute({})
    if (typeof route.loader !== 'function') throw new Error('loader must be a function')
    expect(await route.loader({request: new Request(''), params: {}})).toEqual({
      route: fooRoute,
      queries: {},
    })
    expect(mockedStartSoftNav).toHaveBeenCalledTimes(1)
    expect(dehydrate(getQueryClient())).toEqual({
      queries: [],
      mutations: [],
    })
  })

  test('allows creating an index route with queries, caching loader results', async () => {
    const fooId = appBuilder.createQueryRouteConfig('fooId', {
      path: '/foo/:id',
      queries: [
        {
          queryName: 'payload',
          queryDeps: ({params, searchParams}) => {
            return {
              params: {
                id: Number(params.id),
              },
              searchParams: {
                query: searchParams.get('query'),
              },
            }
          },
          queryFn: ({queryDeps: {params, searchParams}}) => {
            return {
              someField: `args: ${JSON.stringify({params, searchParams})}`,
            }
          },
          type: QueryRouteQueryType.Blocking,
        },
      ],
    })
    expect(fooId).toEqual({
      index: false,
      id: 'fooId',
      generatePath: expect.any(Function),
      path: '/foo/:id',
      isSameRoute: expect.any(Function),
      queries: {
        payload: {
          queryDeps: expect.any(Function),
          queryFn: expect.any(Function),
          type: QueryRouteQueryType.Blocking,
        },
      },
      toRoute: expect.any(Function),
    })

    const queryKey = makeQueryKey({
      appName: 'react-core',
      routeId: 'fooId',
      routePath: '/foo/:id',
      queryName: 'payload',
      queryDeps: {
        params: {
          id: 1,
        },
        searchParams: {
          query: 'abcd',
        },
      },
    })

    const route = fooId.toRoute({})
    if (typeof route.loader !== 'function') throw new Error('loader must be a function')
    await expect(route.loader({request: new Request('/foo/1?query=abcd'), params: {id: '1'}})).resolves.toEqual({
      route: fooId,
      queries: {
        payload: {
          queryConfig: {
            networkMode: 'always',
            refetchOnWindowFocus: false,
            retry: false,
            staleTime: 86400000,
            queryFn: expect.any(Function),
            queryKey,
          },
          type: 'Blocking',
        },
      },
    })
    expect(mockedStartSoftNav).toHaveBeenCalledTimes(1)

    expect(dehydrate(getQueryClient())).toEqual({
      queries: [
        expect.objectContaining({
          queryKey,
          queryHash: JSON.stringify(queryKey),
          state: expect.objectContaining({
            data: {someField: 'args: {"params":{"id":1},"searchParams":{"query":"abcd"}}'},
          }),
        }),
      ],
      mutations: [],
    })
  })

  test('allows creating a non-index route with queries, caching loader results', async () => {
    const fooRoute = appBuilder.createQueryRouteConfig('fooRoute', {
      path: '/foo',
      queries: [
        {
          queryName: 'otherPayload',
          queryDeps: ({params}) => {
            return {
              params,
              searchParams: {},
            }
          },
          queryFn: () => {
            return {
              someOtherField: 'value',
            }
          },
          type: QueryRouteQueryType.Blocking,
        },
      ],
    })
    expect(fooRoute).toEqual({
      index: false,
      id: 'fooRoute',
      generatePath: expect.any(Function),
      queries: {
        otherPayload: {
          queryDeps: expect.any(Function),
          queryFn: expect.any(Function),
          type: QueryRouteQueryType.Blocking,
        },
      },
      toRoute: expect.any(Function),
      path: '/foo',
      isSameRoute: expect.any(Function),
    })

    const queryKey = makeQueryKey({
      appName: 'react-core',
      routeId: 'fooRoute',
      routePath: '/foo',
      queryName: 'otherPayload',
      queryDeps: {
        params: {},
        searchParams: {},
      },
    })

    const route = fooRoute.toRoute({})
    if (typeof route.loader !== 'function') throw new Error('loader must be a function')
    await expect(route.loader({request: new Request(''), params: {}})).resolves.toEqual({
      route: fooRoute,
      queries: {
        otherPayload: {
          queryConfig: {
            networkMode: 'always',
            refetchOnWindowFocus: false,
            retry: false,
            staleTime: 86400000,
            queryFn: expect.any(Function),
            queryKey,
          },
          type: 'Blocking',
        },
      },
    })
    expect(mockedStartSoftNav).toHaveBeenCalledTimes(1)
    expect(dehydrate(getQueryClient())).toEqual({
      queries: [
        expect.objectContaining({
          queryKey,
          state: expect.objectContaining({
            data: {
              someOtherField: 'value',
            },
          }),
        }),
      ],
      mutations: [],
    })
  })

  test('duplicate queryName throws an error', () => {
    expect(() =>
      appBuilder.createQueryRouteConfig('fooRoute', {
        path: '/foo',
        queries: [
          {
            queryName: 'payloadWithSameName',
            queryDeps: ({params}) => {
              return {
                params,
                searchParams: {},
              }
            },
            queryFn: () => {
              return {
                someOtherField: 'value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
          {
            queryName: 'payloadWithSameName',
            queryDeps: ({params}) => {
              return {
                params,
                searchParams: {},
              }
            },
            queryFn: () => {
              return {
                someOtherField: 'value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
        ],
      }),
    ).toThrow('query names cannot be duplicated: `payloadWithSameName` has already been defined for this route.')
  })

  test('QueryRoutes can be built for the correct number of queries', () => {
    expect(() => {
      appBuilder.createQueryRouteConfig('undefinedQueries', {
        path: '/undefined_queries',
        index: true,
      })

      appBuilder.createQueryRouteConfig('noQueries', {
        path: '/no_queries',
        index: true,
        queries: [],
      })

      appBuilder.createQueryRouteConfig('oneQuery', {
        path: '/1_query',
        index: true,
        queries: [
          {
            queryName: 'payload',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
        ],
      })

      appBuilder.createQueryRouteConfig('twoQueries', {
        path: '/2_query',
        index: true,
        queries: [
          {
            queryName: 'payload',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
          {
            queryName: 'payload2',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
        ],
      })

      appBuilder.createQueryRouteConfig('threeQueries', {
        path: '/3_query',
        index: true,
        queries: [
          {
            queryName: 'payload',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
          {
            queryName: 'payload2',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
          {
            queryName: 'payload3',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
        ],
      })

      appBuilder.createQueryRouteConfig('fourQueries', {
        path: '/4_query',
        index: true,
        queries: [
          {
            queryName: 'payload',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
          {
            queryName: 'payload2',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
          {
            queryName: 'payload3',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
          {
            queryName: 'payload4',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
        ],
      })
    }).not.toThrow()
  })

  test('cannot be build for more than the defined number of queries', () => {
    expect(() => {
      appBuilder.createQueryRouteConfig('fiveQueries', {
        id: '5_query',
        path: '/5_queries_is_too_many',
        index: true,
        // @ts-expect-error Queries has a max supported length currently. Extend the types to support more queries.
        queries: [
          {
            queryName: 'payload',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
          {
            queryName: 'payload2',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
          {
            queryName: 'payload3',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
          {
            queryName: 'payload4',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
          {
            queryName: 'payload5',
            queryFn: async () => {
              return {
                someField: 'Index route mocked value',
              }
            },
            type: QueryRouteQueryType.Blocking,
          },
        ],
      })
    }).toThrow('Invalid number of query configs error. 5 queries supplied of a max 4 queries allowed.')
  })

  test('must have a valid javascript identifier as an id', () => {
    expect(() => {
      // eslint-disable-next-line @github-ui/github-monorepo/prefer-route-id-as-var-name
      appBuilder.createQueryRouteConfig('PascalIsNotAllowed', {path: '/'})
    }).toThrow(InvalidIdentifierError)
    expect(() => {
      // eslint-disable-next-line @github-ui/github-monorepo/prefer-route-id-as-var-name
      appBuilder.createQueryRouteConfig('kebab-case', {path: '/'})
    }).toThrow(InvalidIdentifierError)
    expect(() => {
      // eslint-disable-next-line @github-ui/github-monorepo/prefer-route-id-as-var-name
      appBuilder.createQueryRouteConfig('snake_case', {path: '/'})
    }).toThrow(InvalidIdentifierError)
  })

  test('Type correctly indexes queries by queryName', () => {
    const fooBarRoute = appBuilder.createQueryRouteConfig('fooBarRoute', {
      path: '/path/:id',
      queries: [
        mainQuery<{id: string}>(),
        {
          queryName: 'payload',
          queryFn: () => 'payload',
        },
        {
          queryName: 'otherPayload',
          queryFn: () => 'otherPayload',
        },
      ],
    })

    expect(fooBarRoute.queries.mainQuery).toBeDefined()
    expect(fooBarRoute.queries.payload).toBeDefined()
    expect(fooBarRoute.queries.otherPayload).toBeDefined()
    // @ts-expect-error `notDefined` is not a valid queryName
    expect(fooBarRoute.queries.notDefined).toBeUndefined()
  })

  test('generates a path from a set of parameters', () => {
    const fooBarRoute = appBuilder.createQueryRouteConfig('fooBarRoute', {
      path: '/foo/:fooId/bar/:barId',
      index: false,
      queries: [
        {
          queryName: 'otherPayload',
          queryDeps: ({params}) => {
            return {
              params,
              searchParams: {},
            }
          },
          queryFn: () => {
            return {
              someOtherField: 'value',
            }
          },
          type: QueryRouteQueryType.Blocking,
        },
      ],
    })

    expect(
      fooBarRoute.generatePath({
        barId: 'some-bar',
        fooId: 'some-foo',
      }),
    ).toEqual('/foo/some-foo/bar/some-bar')
    expect(
      fooBarRoute.generatePath(
        {
          barId: 'some-bar',
          fooId: 'some-foo',
        },
        {search: '', hash: ''},
      ),
    ).toEqual('/foo/some-foo/bar/some-bar')
    expect(
      fooBarRoute.generatePath(
        {
          barId: 'some-bar',
          fooId: 'some-foo',
        },
        {
          search: 'a=b',
        },
      ),
    ).toEqual('/foo/some-foo/bar/some-bar?a=b')
    expect(
      fooBarRoute.generatePath(
        {
          barId: 'some-bar',
          fooId: 'some-foo',
        },
        {
          search: {a: 'b'},
        },
      ),
    ).toEqual('/foo/some-foo/bar/some-bar?a=b')
    expect(
      fooBarRoute.generatePath(
        {
          barId: 'some-bar',
          fooId: 'some-foo',
        },
        {
          search: new URLSearchParams({a: 'b'}),
        },
      ),
    ).toEqual('/foo/some-foo/bar/some-bar?a=b')
    expect(
      fooBarRoute.generatePath(
        {
          barId: 'some-bar',
          fooId: 'some-foo',
        },
        {
          search: [['a', 'b']],
        },
      ),
    ).toEqual('/foo/some-foo/bar/some-bar?a=b')
    expect(
      fooBarRoute.generatePath(
        {
          barId: 'some-bar',
          fooId: 'some-foo',
        },
        {
          hash: 'some-value',
        },
      ),
    ).toEqual('/foo/some-foo/bar/some-bar#some-value')
    expect(
      fooBarRoute.generatePath(
        {
          barId: 'some-bar',
          fooId: 'some-foo',
        },
        {
          search: 'a=b',
          hash: 'some-value',
        },
      ),
    ).toEqual('/foo/some-foo/bar/some-bar?a=b#some-value')
  })

  test('has stale while revalidate behavior on navigation', async () => {
    jest.useFakeTimers()
    let responseCount = 1
    let deferredPromise = new DeferredPromise<void>()

    function resolveDeferredPromise() {
      act(() => deferredPromise.resolve())
      deferredPromise = new DeferredPromise<void>()
    }
    const pageId = appBuilder.createQueryRouteConfig('pageId', {
      path: '/page/:id',
      queries: [mainQuery<{count: number}>()],
    })

    server.use(
      http.get('/page/:id', async () => {
        await deferredPromise.promise

        return HttpResponse.json({
          payload: {
            pageId: {
              mainQuery: {
                count: responseCount++,
              },
            },
          },
        })
      }),
    )

    function NavLinkItem({id}: {id: string}) {
      return (
        <li key={id}>
          <Link to={pageId.generatePath({id})}>{id}</Link>
        </li>
      )
    }

    const app = appBuilder.createDataRouterAppFromRoutes([
      pageId.toRoute({
        Component: () => {
          const {data} = useRouteQuery(pageId, 'mainQuery')
          return (
            <>
              <nav>
                <ul>
                  {['123', '456'].map(id => {
                    return <NavLinkItem key={id} id={id} />
                  })}
                </ul>
              </nav>
              <main>
                <p>{`count: ${data.count}`}</p>
              </main>
            </>
          )
        },
      }),
    ])
    const {user} = await render(app, '/page/123')
    resolveDeferredPromise()

    expect(await screen.findByText(`count: 1`)).toBeInTheDocument()

    await user.click(screen.getByRole('link', {name: '456'}))
    resolveDeferredPromise()

    expect(await screen.findByText(`count: 2`)).toBeInTheDocument()

    /** advance the timer so we hit the `staleTimeForNavigation` default */
    jest.advanceTimersByTime(DEFAULT_STALE_TIME_FOR_NAVIGATION + 50)
    await user.click(screen.getByRole('link', {name: '123'}))

    /** While the deferred promise is pending we show the stale data from the cache */
    expect(await screen.findByText(`count: 1`)).toBeInTheDocument()

    resolveDeferredPromise()

    /** Once we revalidate, show the new data */
    expect(await screen.findByText(`count: 3`)).toBeInTheDocument()

    jest.useRealTimers()
  })

  describe('embedded data', () => {
    function setup() {
      const testRoute = appBuilder.createQueryRouteConfig('testRoute', {
        path: '/test-route',
        queries: [
          {
            queryName: 'payload',
            queryFn: () => {
              return 'LOADER DATA'
            },
            type: QueryRouteQueryType.Blocking,
          },
        ],
      })
      const componentProfilerOnRenderSpy = jest.fn()
      function Component() {
        const {data, refetch} = useRouteQuery(testRoute, 'payload')
        return (
          <>
            <Link to={testRoute.generatePath({})}>Test Route link</Link>
            <button onClick={() => refetch()}>refetch</button>
            <p>data: {data}</p>
          </>
        )
      }

      const app = appBuilder.createDataRouterAppFromRoutes([
        testRoute.toRoute({
          element: (
            <Profiler id="test-component" onRender={componentProfilerOnRenderSpy}>
              <Component />
            </Profiler>
          ),
        }),
      ])

      return {app, componentProfilerOnRenderSpy}
    }

    test('without embedded data', async () => {
      const {app} = setup()
      render(app, '/test-route')

      expect(await screen.findByText(/data: LOADER DATA/)).toBeInTheDocument()
    })

    test('with embedded data for the correct route and query', async () => {
      const {app} = setup()

      await render(app, '/test-route', {
        embeddedData: {
          payload: {
            testRoute: {
              payload: 'EMBEDDED DATA',
            },
          },
        },
      })

      expect(await screen.findByText(/data: EMBEDDED DATA/)).toBeInTheDocument()
    })

    test('with embedded data for the correct route and wrong query', async () => {
      const {app} = setup()

      await render(app, '/test-route', {
        embeddedData: {
          payload: {
            testRoute: {
              wrongQuery: 'WRONG EMBEDDED DATA',
            },
          },
        },
      })

      expect(screen.queryByText(/data:WRONG EMBEDDED DATA/)).not.toBeInTheDocument()
      expect(await screen.findByText(/data: LOADER DATA/)).toBeInTheDocument()
    })

    test('with embedded data for the correct wrong route and correct query', async () => {
      const {app} = setup()

      await render(app, '/test-route', {
        embeddedData: {
          payload: {
            wrongRoute: {
              payload: 'WRONG EMBEDDED DATA',
            },
          },
        },
      })

      expect(screen.queryByText(/data: WRONG EMBEDDED DATA/)).not.toBeInTheDocument()
      expect(await screen.findByText(/data: LOADER DATA/)).toBeInTheDocument()
    })

    test('subsequent renders do not use embedded data', async () => {
      const {app, componentProfilerOnRenderSpy} = setup()

      const {user} = await render(app, '/test-route', {
        embeddedData: {
          payload: {
            testRoute: {
              payload: 'EMBEDDED DATA',
            },
          },
        },
      })

      // first render is from the initial / embedded data
      expect(await screen.findByText(/data: EMBEDDED DATA/)).toBeInTheDocument()
      expect(componentProfilerOnRenderSpy).toHaveBeenCalledTimes(1)

      await user.click(await screen.findByText('refetch'))

      // second render is from `queryFn` called by the refetch
      expect(await screen.findByText(/data: LOADER DATA/)).toBeInTheDocument()
      expect(componentProfilerOnRenderSpy).toHaveBeenCalledTimes(2)

      await user.click(await screen.findByText('Test Route link'))

      // third and fourth render is from reload caused by the link click
      expect(await screen.findByText(/data: LOADER DATA/)).toBeInTheDocument()
      expect(componentProfilerOnRenderSpy).toHaveBeenCalledTimes(4)

      getQueryClient().clear()
      await user.click(await screen.findByText('Test Route link'))

      // sixth and seventh render is from the link click after the cache is cleared
      expect(await screen.findByText(/data: LOADER DATA/)).toBeInTheDocument()
      expect(componentProfilerOnRenderSpy).toHaveBeenCalledTimes(7)
    })

    test('has stale while revalidate behavior on navigation', async () => {
      jest.useFakeTimers()
      let responseCount = 2
      let deferredPromise = new DeferredPromise<void>()

      function resolveDeferredPromise() {
        act(() => deferredPromise.resolve())
        deferredPromise = new DeferredPromise<void>()
      }
      const pageId = appBuilder.createQueryRouteConfig('pageId', {
        path: '/page/:id',
        queries: [mainQuery<{count: number}>()],
      })

      server.use(
        http.get('/page/:id', async () => {
          await deferredPromise.promise

          return HttpResponse.json({
            payload: {
              pageId: {
                mainQuery: {
                  count: responseCount++,
                },
              },
            },
          })
        }),
      )

      function NavLinkItem({id}: {id: string}) {
        return (
          <li key={id}>
            <Link to={pageId.generatePath({id})}>{id}</Link>
          </li>
        )
      }

      const app = appBuilder.createDataRouterAppFromRoutes([
        pageId.toRoute({
          Component: () => {
            const {data} = useRouteQuery(pageId, 'mainQuery')
            return (
              <>
                <nav>
                  <ul>
                    {['123', '456'].map(id => {
                      return <NavLinkItem key={id} id={id} />
                    })}
                  </ul>
                </nav>
                <main>
                  <p>{`count: ${data.count}`}</p>
                </main>
              </>
            )
          },
        }),
      ])
      const {user} = await render(app, '/page/123', {
        embeddedData: {
          payload: {
            pageId: {
              mainQuery: {
                count: 1,
              },
            },
          },
        },
      })
      resolveDeferredPromise()

      expect(await screen.findByText(`count: 1`)).toBeInTheDocument()

      await user.click(screen.getByRole('link', {name: '456'}))
      resolveDeferredPromise()

      expect(await screen.findByText(`count: 2`)).toBeInTheDocument()

      /** advance the timer so we hit the `staleTimeForNavigation` default */
      jest.advanceTimersByTime(DEFAULT_STALE_TIME_FOR_NAVIGATION + 50)
      await user.click(screen.getByRole('link', {name: '123'}))

      /** While the deferred promise is pending we show the stale data from the cache */
      expect(await screen.findByText(`count: 1`)).toBeInTheDocument()

      resolveDeferredPromise()

      /** Once we revalidate, show the new data */
      expect(await screen.findByText(`count: 3`)).toBeInTheDocument()

      jest.useRealTimers()
    })
  })
})

class DeferredPromise<T> {
  promise: Promise<T>
  resolve!: (value: T | PromiseLike<T>) => void
  reject!: (reason?: unknown) => void

  constructor() {
    this.promise = new Promise<T>((resolve, reject) => {
      this.resolve = resolve
      this.reject = reject
    })
  }
}
