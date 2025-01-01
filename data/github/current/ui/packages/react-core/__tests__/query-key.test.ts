import {makeQueryKey} from '../query-key'

describe('makeQueryKey', () => {
  it('should generate a unique query key with given params', () => {
    const appName = 'testApp'
    const routeId = 'testRouteId'
    const routePath = '/test/path/:testId'
    const queryName = 'testQuery'
    const queryDeps = {repoId: '143', commentId: '65'}

    const result = makeQueryKey({appName, routeId, routePath, queryName, queryDeps})

    expect(result).toEqual([appName, routeId, routePath, queryName, queryDeps])
  })

  it('should handle the default route and search param format', () => {
    const appName = 'testApp'
    const routeId = 'testRouteId'
    const routePath = '/test/path/:testId'
    const queryName = 'testQuery'
    const searchParams = new URLSearchParams('q=search')
    const queryDeps = {
      routeParams: {repoId: '143', commentId: '65'},
      searchParams,
    }

    const result = makeQueryKey({appName, routeId, routePath, queryName, queryDeps})

    expect(result).toEqual([appName, routeId, routePath, queryName, queryDeps])
  })

  it('should return the same value for subsequent calls', () => {
    const result1 = makeQueryKey({
      appName: 'call',
      routeId: 'testRouteId',
      routePath: '/test/path/:testId',
      queryName: 'testQuery',
      queryDeps: {repoId: '143', commentId: '65', search: 'test'},
    })
    const result2 = makeQueryKey({
      appName: 'call',
      routeId: 'testRouteId',
      routePath: '/test/path/:testId',
      queryName: 'testQuery',
      queryDeps: {search: 'test', repoId: '143', commentId: '65'},
    })

    expect(result1).toMatchObject(result2)
  })

  it('should handle empty queryDeps object', () => {
    const appName = 'testApp'
    const routeId = 'testRouteId'
    const routePath = '/test/path/:testId'
    const queryName = 'testQuery'
    const queryDeps = {}

    const result = makeQueryKey({appName, routeId, routePath, queryName, queryDeps})

    expect(result).toEqual([appName, routeId, routePath, queryName, queryDeps])
  })
})
