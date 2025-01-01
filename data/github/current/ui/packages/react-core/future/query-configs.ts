import type {queryOptions, QueryMeta} from '@tanstack/react-query'
import {QueryRouteQueryType, type QueryDepsFn} from './data-router-types'
import {queryFnFetch} from './query-fn-fetch'

// note the `any` for `RoutePath` here means we don't get fully typed `params` object in the queryDeps function
// but that should be fine since that's only internal to reusable query configs.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type RelaxedQueryDepsFn<T> = (...args: Parameters<QueryDepsFn<any>>) => T

type QueryOptions<Deps> = Omit<Parameters<typeof queryOptions>[0], 'queryFn' | 'queryKey'> & {
  /**
   * Specialized version of query deps that returns the `string` url path from which to request data
   */
  queryDeps?: RelaxedQueryDepsFn<Deps>
} & {staleTimeForNavigation?: number}

/**
 * A relaxed version of {@link QueryRouteQueryConfig} that allows for a more independent API
 * at the cost of some type safety. Specifically, it relaxes many of the generics from `QueryRouteQueryConfig`
 */
type RelaxedQueryRouteQueryConfig<Res, Deps, QueryName extends string> = QueryOptions<Deps> & {
  queryName: QueryName
  /**
   * The queryFn to call.
   * This accepts dependencies returned from the queryDeps function if one exists and returns a response to cache.
   */
  queryFn: (
    queryKey: {
      appName: string
      routeId: string
      routePath: string
      queryName: QueryName
      queryDeps: Deps
    },
    opts: {signal: AbortSignal; meta: QueryMeta | undefined},
  ) => Promise<Res> // This is not entirely true for mainQuery, but it's there to match QueryRouteQueryConfig
  /**
   * The {@link QueryRouteQueryType} type of query to initiate
   */
  type?: QueryRouteQueryType
}

type QueryFnFetchDeps = Parameters<typeof queryFnFetch>[0]['queryDeps']

/**
 * Provides a shorthand for creating a `QueryConfig` that reads `payload[routeId].mainQuery` from `embeddedData` on
 * page load and via `json` request to the current matched route on soft-navigation. This is the most common use
 * case for route-bound query data and should be all that is needed to provide data for most pages.
 */
export function mainQuery<Res>({...opts}: QueryOptions<QueryFnFetchDeps> = {}): RelaxedQueryRouteQueryConfig<
  Res,
  QueryFnFetchDeps,
  'mainQuery'
> {
  return {
    queryName: 'mainQuery',
    queryDeps: ({pathname, searchParams}) => ({pathname, searchParams}),
    queryFn: async ({routeId, queryDeps}) => {
      const json = await queryFnFetch<{payload: Record<string, Record<'mainQuery', Res>>}>({queryDeps})
      const routePayload = json.payload?.[routeId]
      if (!routePayload) {
        throw new Error(`Unable to find payload for route Id: ${routeId}`)
      }
      if (!('mainQuery' in routePayload)) {
        throw new Error(`Payload for route ID (${routeId}) does not have a 'mainQuery' property`)
      }
      // This casting is not entirely pretty. But it's necessary. Because `mainQuery` returns a slightly
      // different type than what will be used in Query Route, the `queryFn` has to return of type Res,
      // but in this context, we *know* we're going to use the `select` callback later. So we have
      // to cheat the types to satisfy but still get the right behavior we need.
      return routePayload as Res
    },
    type: QueryRouteQueryType.Blocking,
    select: data => {
      return (data as Record<'mainQuery', Res>).mainQuery
    },
    ...opts,
  }
}
