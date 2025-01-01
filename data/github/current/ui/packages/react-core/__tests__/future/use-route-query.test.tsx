// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {screen} from '@testing-library/react'
import {isRouteErrorResponse, Outlet, useRouteError} from 'react-router-dom'
import {render} from '../../future/test-utils/Render'
import {useRouteQuery} from '../../future/use-route-query'
import {DataRouterApplicationBuilder} from '../../future/data-router-application'
import {QueryRouteQueryType} from '../../future/data-router-types'

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
  test('returns the data for both parent and child routes', async () => {
    render(app, '/will-succeed')

    expect(await screen.findByText('{"someLayoutField":"exists"}')).toBeInTheDocument()
    expect(await screen.findByText('{"someField":"exists"}')).toBeInTheDocument()
  })
  test('throws to an error boundary when an invalid route data is accessed', async () => {
    jest.spyOn(console, 'error').mockImplementation()
    render(app, '/going-to-display-error')
    expect(await screen.findByText('Cannot read data from unmounted routes')).toBeInTheDocument()
  })

  test('errors when reading child route from a parent route', async () => {
    jest.spyOn(console, 'error').mockImplementation()
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

    expect(await screen.findByText('Cannot read data from child routes')).toBeInTheDocument()
  })
})
