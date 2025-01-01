import {startSoftNav} from '@github-ui/soft-nav/state'
import {beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {delay, http, HttpResponse, msw} from '@github-ui/tests/msw'
import {dehydrate} from '@tanstack/react-query'
import {screen, waitFor} from '@testing-library/react'
import {Profiler} from 'react'
import {Link, Outlet} from 'react-router-dom'

import {DataRouterApplicationBuilder, InvalidIdentifierError} from '../future/data-router-application'
import {QueryRouteQueryType} from '../future/data-router-types'
import {mainQuery} from '../future/main-query'
import {render} from '../future/test-utils/Render'
import {useRouteQuery} from '../future/use-route-query'
import {getQueryClient} from '../query-client'
import {makeQueryKey} from '../query-key'

const appBuilder = DataRouterApplicationBuilder.create('react-core')

vi.mock('@github-ui/soft-nav/state', async () => {
  // eslint-disable-next-line @typescript-eslint/consistent-type-imports
  const actual = await vi.importActual<typeof import('@github-ui/soft-nav/state')>('@github-ui/soft-nav/state')
  return {
    ...actual,
    startSoftNav: vi.fn().mockImplementation(actual.startSoftNav),
  }
})

const mockedStartSoftNav = vi.mocked(startSoftNav)

const TestComponent = () => <p>Bar</p>
const TestOutletComponent = () => (
  <div>
    <Outlet />
  </div>
)

describe('queryRoute', () => {
  beforeEach(() => {
    mockedStartSoftNav.mockReset()
  })
  it('correctly passes urls for nested routes', async () => {
    const queryDepsSpy = vi.fn()
    const queryFnSpy = vi.fn()

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

  it('correctly passes search params', async () => {
    const queryDepsSpy = vi.fn()
    const queryFnSpy = vi.fn()

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

  it('allows creating an index route', async () => {
    const routeConfig = appBuilder.createQueryRouteConfig('routeConfig', {
      path: '/foo',
      index: true,
    })
    expect(routeConfig).toMatchObject({
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

  it('allows creating a non-index route', async () => {
    const fooRoute = appBuilder.createQueryRouteConfig('fooRoute', {
      path: '/foo',
    })
    expect(fooRoute).toMatchObject({
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

  it('allows creating an index route with queries, caching loader results', async () => {
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
    expect(fooId).toMatchObject({
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

  it('allows creating a non-index route with queries, caching loader results', async () => {
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
    expect(fooRoute).toMatchObject({
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

  it('duplicate queryName throws an error', () => {
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

  it('QueryRoutes can be built for the correct number of queries', () => {
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

  it('cannot be build for more than the defined number of queries', () => {
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

  it('must have a valid javascript identifier as an id', () => {
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

  it('Type correctly indexes queries by queryName', () => {
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

  it('generates a path from a set of parameters', () => {
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

  it('has stale while revalidate behavior on navigation', async () => {
    let responseCount = 1

    const pageId = appBuilder.createQueryRouteConfig('pageId', {
      path: '/page/:id',
      queries: [mainQuery<{count: number}>({staleTimeForNavigation: 0})],
    })

    msw.use(
      http.get('/page/:id', async () => {
        await delay(100)
        return HttpResponse.json({
          payload: {
            pageId: {
              count: responseCount++,
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
    render(app, '/page/123')

    expect(await screen.findByText(`count: 1`)).toBeInTheDocument()

    await userEvent.click(screen.getByRole('link', {name: '456'}))

    expect(await screen.findByText(`count: 2`)).toBeInTheDocument()

    await userEvent.click(screen.getByRole('link', {name: '123'}))

    /** While the deferred promise is pending we show the stale data from the cache */
    expect(await screen.findByText(`count: 1`)).toBeInTheDocument()

    // /** Once we revalidate, show the new data */
    expect(await screen.findByText(`count: 3`)).toBeInTheDocument()
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
      const componentProfilerOnRenderSpy = vi.fn()
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

    it('without embedded data', async () => {
      const {app} = setup()
      render(app, '/test-route')

      expect(await screen.findByText(/data: LOADER DATA/)).toBeInTheDocument()
    })

    it('with embedded data for the correct route and query', async () => {
      const {app} = setup()

      render(app, '/test-route', {
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

    it('with embedded data for the correct route and wrong query', async () => {
      const {app} = setup()

      render(app, '/test-route', {
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

    it('with embedded data for the correct wrong route and correct query', async () => {
      const {app} = setup()

      render(app, '/test-route', {
        embeddedData: {
          payload: {
            wrongRoute: 'WRONG EMBEDDED DATA',
          },
        },
      })

      expect(screen.queryByText(/data: WRONG EMBEDDED DATA/)).not.toBeInTheDocument()
      expect(await screen.findByText(/data: LOADER DATA/)).toBeInTheDocument()
    })

    it('subsequent renders do not use embedded data', async () => {
      const {app, componentProfilerOnRenderSpy} = setup()

      render(app, '/test-route', {
        embeddedData: {
          payload: {
            testRoute: {
              payload: 'EMBEDDED DATA',
            },
          },
        },
      })

      // Check that embedded data is initially used
      expect(await screen.findByText(/data: EMBEDDED DATA/)).toBeInTheDocument()

      // Store the initial call count to track relative changes
      const initialRenderCount = componentProfilerOnRenderSpy.mock.calls.length
      expect(initialRenderCount).toBeGreaterThan(0)

      // Test refetch behavior
      await userEvent.click(await screen.findByText('refetch'))
      expect(await screen.findByText(/data: LOADER DATA/)).toBeInTheDocument()

      // Verify that at least one more render happened after refetch
      const afterRefetchCount = componentProfilerOnRenderSpy.mock.calls.length
      expect(afterRefetchCount).toBeGreaterThan(initialRenderCount)

      // Test link navigation behavior
      await userEvent.click(await screen.findByText('Test Route link'))
      expect(await screen.findByText(/data: LOADER DATA/)).toBeInTheDocument()

      // Verify that at least one more render happened after link click
      const afterLinkClickCount = componentProfilerOnRenderSpy.mock.calls.length
      expect(afterLinkClickCount).toBeGreaterThan(afterRefetchCount)

      // Test cache clearing behavior
      getQueryClient().clear()
      await userEvent.click(await screen.findByText('Test Route link'))

      // Verify data loads correctly after cache clear
      expect(await screen.findByText(/data: LOADER DATA/)).toBeInTheDocument()

      // Verify more renders happened after cache clear and link click
      await waitFor(() => {
        const finalRenderCount = componentProfilerOnRenderSpy.mock.calls.length
        expect(finalRenderCount).toBeGreaterThan(afterLinkClickCount)
      })
    })

    it('has stale while revalidate behavior on navigation', async () => {
      let responseCount = 1

      const pageId = appBuilder.createQueryRouteConfig('pageId', {
        path: '/page/:id',
        queries: [mainQuery<{count: number}>({staleTimeForNavigation: 0})],
      })

      msw.use(
        http.get('/page/:id', async () => {
          await delay(100)
          return HttpResponse.json({
            payload: {
              pageId: {
                count: responseCount++,
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
      render(app, '/page/123', {
        embeddedData: {
          payload: {
            pageId: {
              count: 1,
            },
          },
        },
      })

      expect(await screen.findByText(`count: 1`)).toBeInTheDocument()

      await userEvent.click(screen.getByRole('link', {name: '456'}))

      expect(await screen.findByText(`count: 2`)).toBeInTheDocument()

      await userEvent.click(screen.getByRole('link', {name: '123'}))

      /** While the deferred promise is pending we show the stale data from the cache */
      expect(await screen.findByText(`count: 1`)).toBeInTheDocument()

      /** Once we revalidate, show the new data */
      expect(await screen.findByText(`count: 3`)).toBeInTheDocument()
    })
  })
})
