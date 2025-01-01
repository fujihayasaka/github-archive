import {describe, expect, it} from '@github-ui/tests'

import type {QueryOptionsWithKey} from '../../future/query-route'
import {getTitleFromQueryClient} from '../../future/TitleManager'
import {getQueryClient} from '../../query-client'
import type {RouteQueryKey} from '../../query-key'

describe('getTitleFromQueryClient', () => {
  it('handles title directly on query data', () => {
    const queryClient = getQueryClient()
    const queryKey: RouteQueryKey = ['appName', 'routeId', 'routePath', 'queryName', {}]
    const queryData = {title: 'page title'}
    queryClient.setQueryData(queryKey, queryData)

    const queryConfig: QueryOptionsWithKey = {
      queryKey,
      queryFn: () => {
        throw new Error('should not be called')
      },
    }
    expect(getTitleFromQueryClient(queryClient, queryConfig)).toEqual('page title')
  })

  it('handles title on meta in query data', () => {
    const queryClient = getQueryClient()
    const queryKey: RouteQueryKey = ['appName', 'routeId', 'routePath', 'queryName', {}]
    const queryData = {meta: {title: 'page title'}}
    queryClient.setQueryData(queryKey, queryData)

    const queryConfig: QueryOptionsWithKey = {
      queryKey,
      queryFn: () => {
        throw new Error('should not be called')
      },
    }
    expect(getTitleFromQueryClient(queryClient, queryConfig)).toEqual('page title')
  })
})
