// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {describe, expect, it, vi} from '@github-ui/tests'

import {DataRouterApplicationBuilder} from '../../future/data-router-application'
import {QueryRouteQueryType} from '../../future/data-router-types'
import {useRouteQuery} from '../../future/use-route-query'

vi.mock('../../future/use-route-query', () => {
  return {
    useRouteQuery: vi.fn(),
  }
})
const mockedUseRouteQuery = vi.mocked(useRouteQuery)

const builder = DataRouterApplicationBuilder.create('react-core')

const route = builder.createQueryRouteConfig('route', {
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
    {
      queryName: 'deferred',
      queryDeps: () => ({}),
      queryFn: () => {
        return {someDeferredField: 'exists'}
      },
      type: QueryRouteQueryType.Deferred,
    },
  ],
})
const route2 = builder.createQueryRouteConfig('route2', {
  path: '/will-succeed',
  queries: [
    {
      queryName: 'payload',
      queryDeps: () => ({}),
      queryFn: () => {
        return {someField: 'exists'}
      },
    },
  ],
})

describe('useRouteQuery types', () => {
  it('has valid return types for both deferred and blocking queries', async () => {
    mockedUseRouteQuery.mockImplementation((routeDefinition, type) => {
      if (routeDefinition === route) {
        if (type === 'payload') {
          return {data: {someField: 'exists'}}
        }
        if (type === 'deferred') {
          return {data: undefined}
        }
      } else if (routeDefinition === route2) {
        if (type === 'payload') {
          return {data: undefined}
        }
      }
      throw new Error('Invalid route definition')
    })

    expect(route.queries.payload).toHaveProperty('type', QueryRouteQueryType.Blocking)
    expect(route.queries.deferred).toHaveProperty('type', QueryRouteQueryType.Deferred)
    // @ts-expect-error this is not a defined query
    expect(route.queries.notExistant).not.toBeDefined()

    expect(route2.queries.payload).not.toHaveProperty('type')
    // @ts-expect-error this is not a defined query
    expect(route2.queries.notExistant).not.toBeDefined()

    const {data: blockingPayload} = useRouteQuery(route, 'payload')
    expect(blockingPayload.someField).toBeDefined()

    const {data: deferredPayload2} = useRouteQuery(route2, 'payload')
    expect(
      () =>
        // @ts-expect-error this field is potentially undefined
        deferredPayload2.someField,
    ).toThrow("Cannot read properties of undefined (reading 'someField')")

    const {data: deferredPayload} = useRouteQuery(route, 'deferred')
    expect(
      () =>
        // @ts-expect-error this field is potentially undefined
        deferredPayload.someDeferredField,
    ).toThrow("Cannot read properties of undefined (reading 'someDeferredField')")
  })
})
