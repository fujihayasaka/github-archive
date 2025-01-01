// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {describe, expect, it} from '@github-ui/tests'
import {screen} from '@testing-library/react'

import {DataRouterApplicationBuilder} from '../../future/data-router-application'
import {QueryRouteQueryType} from '../../future/data-router-types'
import {render} from '../../future/test-utils/Render'
import {useIsRouteMounted} from '../../future/use-is-route-mounted'

const builder = DataRouterApplicationBuilder.create('react-core')

describe('useIsRouteMounted', () => {
  it('returns true if route is mounted', async () => {
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
          const childIsMounted = useIsRouteMounted(childRoute)
          return <>{childIsMounted ? 'Child is mounted' : 'Child is not mounted'}</>
        },
        children: [
          childRoute.toRoute({
            element: <div>Child</div>,
          }),
        ],
      }),
    ])

    render(testApp, '/child')
    expect(await screen.findByText('Child is mounted')).toBeInTheDocument()
  })

  it('returns false if route is unmounted', async () => {
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
          const childIsMounted = useIsRouteMounted(childRoute)
          return <>{childIsMounted ? 'Child is mounted' : 'Child is not mounted'}</>
        },
        children: [
          childRoute.toRoute({
            element: <div>Child</div>,
          }),
        ],
      }),
    ])

    render(testApp, '/')
    expect(await screen.findByText('Child is not mounted')).toBeInTheDocument()
  })
})
