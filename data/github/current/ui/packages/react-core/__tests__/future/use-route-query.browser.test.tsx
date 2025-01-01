// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {describe, expect, it, vi} from '@github-ui/tests'
import {screen} from '@testing-library/react'
import {isRouteErrorResponse, Outlet, useRouteError} from 'react-router-dom'

import {DataRouterApplicationBuilder} from '../../future/data-router-application'
import {QueryRouteQueryType} from '../../future/data-router-types'
import {render} from '../../future/test-utils/Render'
import {
  useChildRouteQuery,
  useRouteQuery,
  useSuspenseChildRouteQuery,
  useSuspenseRouteQuery,
} from '../../future/use-route-query'

const builder = DataRouterApplicationBuilder.create('react-core')
const layoutRoute = builder.createQueryRouteConfig('layoutRoute', {
  path: '/',
  queries: [
    {
      queryName: 'layout',
      queryDeps: () => ({}),
      queryFn: () => {
        return {someLayoutField: 'exists'}
      },
      type: QueryRouteQueryType.Blocking,
    },
  ],
})
const routeThatAccessesRoute1DataCorrectly = builder.createQueryRouteConfig('routeThatAccessesRoute1DataCorrectly', {
  path: '/will-succeed',
  queries: [
    {
      queryName: 'payload',
      queryDeps: () => ({}),
      queryFn: () => {
        return {someField: 'exists'}
      },
      type: QueryRouteQueryType.Blocking,
    },
  ],
})

const routeThatAccessesRoute1DataIncorrectly = builder.createQueryRouteConfig(
  'routeThatAccessesRoute1DataIncorrectly',
  {
    path: '/going-to-display-error',
    queries: [
      {
        queryName: 'payload',
        queryDeps: () => ({}),
        queryFn: () => {
          return {someField: 'does not exist'}
        },
        type: QueryRouteQueryType.Blocking,
      },
    ],
  },
)

const app = builder.createDataRouterAppFromRoutes([
  layoutRoute.toRoute({
    element: <Outlet />,
    children: [
      routeThatAccessesRoute1DataCorrectly.toRoute({
        Component: () => {
          const {data: child} = useRouteQuery(routeThatAccessesRoute1DataCorrectly, 'payload')
          const {data: parent} = useRouteQuery(layoutRoute, 'layout')
          return (
            <>
              <p data-testid="parent-data">{JSON.stringify(parent)}</p>
              <p data-testid="child-data">{JSON.stringify(child)}</p>
            </>
          )
        },
      }),
      routeThatAccessesRoute1DataIncorrectly.toRoute({
        ErrorBoundary: () => {
          const routeError = useRouteError()
          if (isRouteErrorResponse(routeError)) {
            return (
              <>
                <h1>
                  {routeError.status} {routeError.statusText}
                </h1>
                <p>{routeError.data}</p>
              </>
            )
          } else if (routeError instanceof Error) {
            return (
              <div>
                <h1>Error</h1>
                <p>{routeError.message}</p>
                <p>The stack trace is:</p>
                <pre>{routeError.stack}</pre>
              </div>
            )
          } else {
            return <h1>Unknown Error</h1>
          }
        },
        Component: () => {
          const {data} = useRouteQuery(routeThatAccessesRoute1DataCorrectly, 'payload')
          return <p>{JSON.stringify(data)}</p>
        },
      }),
    ],
  }),
])

describe('useRouteQuery', () => {
  it('returns the data for both parent and child routes', async () => {
    render(app, '/will-succeed')

    expect(await screen.findByText('{"someLayoutField":"exists"}')).toBeInTheDocument()
    expect(await screen.findByText('{"someField":"exists"}')).toBeInTheDocument()
  })
  it('throws to an error boundary when an invalid route data is accessed', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    render(app, '/going-to-display-error')
    expect(await screen.findByText(/Cannot read data from unmounted route/, {selector: 'p'})).toBeInTheDocument()
  })

  it('errors when reading child route from a parent route', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const parentRoute = builder.createQueryRouteConfig('parentRoute', {
      path: '/',
    })

    const childRoute = builder.createQueryRouteConfig('childRoute', {
      path: '/child',
      queries: [
        {
          queryName: 'mainQuery',
          queryFn: () => {
            return {some: 'data'}
          },
          type: QueryRouteQueryType.Blocking,
        },
      ],
    })

    const testApp = builder.createDataRouterAppFromRoutes([
      parentRoute.toRoute({
        Component: () => {
          useRouteQuery(childRoute, 'mainQuery')
          return <Outlet />
        },
        ErrorBoundary: () => {
          const routeError = useRouteError()
          if (routeError instanceof Error) {
            return <p>{routeError.message}</p>
          }
          return null
        },
        children: [
          childRoute.toRoute({
            element: <div />,
          }),
        ],
      }),
    ])

    render(testApp, '/child')

    expect(await screen.findByText(/Cannot read data from child route/, {selector: 'p'})).toBeInTheDocument()
  })

  it('allows reading child route from a parent route with useChildRouteQuery', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const parentRoute = builder.createQueryRouteConfig('parentRoute', {
      path: '/',
    })

    const childRoute = builder.createQueryRouteConfig('childRoute', {
      path: '/child',
      queries: [
        {
          queryName: 'mainQuery',
          queryFn: () => {
            return {some: 'data'}
          },
          type: QueryRouteQueryType.Blocking,
        },
      ],
    })

    const testApp = builder.createDataRouterAppFromRoutes([
      parentRoute.toRoute({
        Component: () => {
          useChildRouteQuery(childRoute, 'mainQuery')
          return <Outlet />
        },
        ErrorBoundary: () => {
          const routeError = useRouteError()
          if (routeError instanceof Error) {
            return <p>{routeError.message}</p>
          }
          return null
        },
        children: [
          childRoute.toRoute({
            element: <div>Child</div>,
          }),
        ],
      }),
    ])

    render(testApp, '/child')
    expect(await screen.findByText('Child')).toBeInTheDocument()
  })

  it('throws when reading unmounted child route from a parent route with useChildRouteQuery', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const parentRoute = builder.createQueryRouteConfig('parentRoute', {
      path: '/',
    })

    const childRoute = builder.createQueryRouteConfig('childRoute', {
      path: '/child',
      queries: [
        {
          queryName: 'mainQuery',
          queryFn: () => {
            return {some: 'data'}
          },
          type: QueryRouteQueryType.Blocking,
        },
      ],
    })

    const testApp = builder.createDataRouterAppFromRoutes([
      parentRoute.toRoute({
        Component: () => {
          useChildRouteQuery(childRoute, 'mainQuery')
          return <Outlet />
        },
        ErrorBoundary: () => {
          const routeError = useRouteError()
          if (routeError instanceof Error) {
            return <p>{routeError.message}</p>
          }
          return null
        },
        children: [
          childRoute.toRoute({
            element: <div>Child</div>,
          }),
        ],
      }),
    ])

    render(testApp, '/')
    expect(await screen.findByText(/Cannot read data from unmounted route/, {selector: 'p'})).toBeInTheDocument()
  })

  it('suspense: returns the data for both parent and child routes', async () => {
    const Parent = () => {
      const {data: parent} = useSuspenseRouteQuery(layoutRoute, 'layout')
      return <p data-testid="parent-data">{JSON.stringify(parent)}</p>
    }

    const Child = () => {
      const {data: child} = useSuspenseRouteQuery(routeThatAccessesRoute1DataCorrectly, 'payload')
      return <p data-testid="child-data">{JSON.stringify(child)}</p>
    }

    const testApp = builder.createDataRouterAppFromRoutes([
      layoutRoute.toRoute({
        element: (
          <>
            <Parent />
            <Outlet />
          </>
        ),
        children: [
          routeThatAccessesRoute1DataCorrectly.toRoute({
            Component: Child,
          }),
        ],
      }),
    ])

    render(testApp, '/will-succeed')

    expect(await screen.findByText('{"someLayoutField":"exists"}')).toBeInTheDocument()
    expect(await screen.findByText('{"someField":"exists"}')).toBeInTheDocument()
  })

  it('suspense: throws to an error boundary when an invalid route data is accessed', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    render(app, '/going-to-display-error')
    expect(await screen.findByText(/Cannot read data from unmounted route/, {selector: 'p'})).toBeInTheDocument()
  })

  it('suspense: errors when reading child route from a parent route', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const parentRoute = builder.createQueryRouteConfig('parentRoute', {
      path: '/',
    })

    const childRoute = builder.createQueryRouteConfig('childRoute', {
      path: '/child',
      queries: [
        {
          queryName: 'mainQuery',
          queryFn: () => {
            return {some: 'data'}
          },
          type: QueryRouteQueryType.Blocking,
        },
      ],
    })

    const testApp = builder.createDataRouterAppFromRoutes([
      parentRoute.toRoute({
        Component: () => {
          useSuspenseRouteQuery(childRoute, 'mainQuery')
          return <Outlet />
        },
        ErrorBoundary: () => {
          const routeError = useRouteError()
          if (routeError instanceof Error) {
            return <p>{routeError.message}</p>
          }
          return null
        },
        children: [
          childRoute.toRoute({
            element: <div />,
          }),
        ],
      }),
    ])

    render(testApp, '/child')

    expect(await screen.findByText(/Cannot read data from child route/, {selector: 'p'})).toBeInTheDocument()
  })

  it('suspense: allows reading child route from a parent route with useChildRouteQuery', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const parentRoute = builder.createQueryRouteConfig('parentRoute', {
      path: '/',
    })

    const childRoute = builder.createQueryRouteConfig('childRoute', {
      path: '/child',
      queries: [
        {
          queryName: 'mainQuery',
          queryFn: () => {
            return {some: 'data'}
          },
          type: QueryRouteQueryType.Blocking,
        },
      ],
    })

    const testApp = builder.createDataRouterAppFromRoutes([
      parentRoute.toRoute({
        Component: () => {
          useChildRouteQuery(childRoute, 'mainQuery')
          return <Outlet />
        },
        ErrorBoundary: () => {
          const routeError = useRouteError()
          if (routeError instanceof Error) {
            return <p>{routeError.message}</p>
          }
          return null
        },
        children: [
          childRoute.toRoute({
            element: <div>Child</div>,
          }),
        ],
      }),
    ])

    render(testApp, '/child')
    expect(await screen.findByText('Child')).toBeInTheDocument()
  })

  it('suspense: throws when reading unmounted child route from a parent route with useSuspenseChildRouteQuery', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})
    const parentRoute = builder.createQueryRouteConfig('parentRoute', {
      path: '/',
    })

    const childRoute = builder.createQueryRouteConfig('childRoute', {
      path: '/child',
      queries: [
        {
          queryName: 'mainQuery',
          queryFn: () => {
            return {some: 'data'}
          },
          type: QueryRouteQueryType.Blocking,
        },
      ],
    })

    const testApp = builder.createDataRouterAppFromRoutes([
      parentRoute.toRoute({
        Component: () => {
          useSuspenseChildRouteQuery(childRoute, 'mainQuery')
          return <Outlet />
        },
        ErrorBoundary: () => {
          const routeError = useRouteError()
          if (routeError instanceof Error) {
            return <p>{routeError.message}</p>
          }
          return null
        },
        children: [
          childRoute.toRoute({
            element: <div>Child</div>,
          }),
        ],
      }),
    ])

    render(testApp, '/')
    expect(await screen.findByText(/Cannot read data from unmounted route/, {selector: 'p'})).toBeInTheDocument()
  })

  it('suspense: handles deferred queries properly', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})

    const deferredRoute = builder.createQueryRouteConfig('deferredRoute', {
      path: '/deferred',
      queries: [
        {
          queryName: 'deferredData',
          queryDeps: () => ({}),
          queryFn: () => {
            return {deferredField: 'loaded'}
          },
          type: QueryRouteQueryType.Deferred,
        },
      ],
    })

    const DeferredComponent = () => {
      const {data} = useSuspenseRouteQuery(deferredRoute, 'deferredData')
      return <p data-testid="deferred-data">{JSON.stringify(data)}</p>
    }

    const testApp = builder.createDataRouterAppFromRoutes([
      deferredRoute.toRoute({
        Component: DeferredComponent,
      }),
    ])

    render(testApp, '/deferred')
    expect(await screen.findByText('{"deferredField":"loaded"}')).toBeInTheDocument()
  })

  it('suspense: passes query overrides to useSuspenseQuery', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {})

    const queryFn = vi.fn(() => {
      return {customField: 'custom value'}
    })

    const customRoute = builder.createQueryRouteConfig('customRoute', {
      path: '/custom',
      queries: [
        {
          queryName: 'customData',
          queryDeps: () => ({}),
          queryFn,
          type: QueryRouteQueryType.Blocking,
        },
      ],
    })

    const CustomComponent = () => {
      // Use custom staleTime to verify override is passed
      const {data} = useSuspenseRouteQuery(customRoute, 'customData', {staleTime: 0})
      return <p data-testid="custom-data">{JSON.stringify(data)}</p>
    }

    const testApp = builder.createDataRouterAppFromRoutes([
      customRoute.toRoute({
        Component: CustomComponent,
      }),
    ])

    render(testApp, '/custom')
    expect(await screen.findByText('{"customField":"custom value"}')).toBeInTheDocument()
    expect(queryFn).toHaveBeenCalled()
  })
})
