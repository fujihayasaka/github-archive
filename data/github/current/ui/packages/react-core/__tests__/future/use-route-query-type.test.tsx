// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {DataRouterApplicationBuilder} from '../../future/data-router-application'
import {QueryRouteQueryType} from '../../future/data-router-types'
import {useRouteQuery} from '../../future/use-route-query'

jest.mock('../../future/use-route-query', () => {
  return {
    useRouteQuery: jest.fn(),
  }
})
const mockedUseRouteQuery = jest.mocked(useRouteQuery)

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
  test('has valid return types for both deferred and blocking queries', async () => {
    // @ts-expect-error this isn't a full return type, but we're only testing a portion of it so that's ok
    mockedUseRouteQuery.mockImplementation((_, type) => {
      if (type === 'payload') {
        return {data: {someField: 'exists'}}
      }
      if (type === 'deferred') {
        return {data: undefined}
      }
    })

    expect(route.queries.payload).toHaveProperty('type', QueryRouteQueryType.Blocking)
    expect(route.queries.deferred).toHaveProperty('type', QueryRouteQueryType.Deferred)
    // @ts-expect-error this is not a defined query
    expect(route.queries.notExistant).not.toBeDefined()

    expect(route2.queries.payload).not.toHaveProperty('type')
    // @ts-expect-error this is not a defined query
    expect(route2.queries.notExistant).not.toBeDefined()

    expect(() => {
      const {data: blockingPayload} = useRouteQuery(route, 'payload')
      expect(blockingPayload.someField).toBeDefined()

      const {data: blockingPayload2} = useRouteQuery(route2, 'payload')
      expect(blockingPayload2.someField).toBeDefined()

      const {data: deferredPayload} = useRouteQuery(route, 'deferred')
      expect(
        () =>
          // @ts-expect-error this field is potentially undefined
          deferredPayload.someDeferredField,
      ).toThrow("Cannot read properties of undefined (reading 'someDeferredField')")
    }).not.toThrow()
  })
})
