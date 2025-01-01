import {getAppTypeHeader} from '@github-ui/fetch-headers'
import type {QueryMeta, queryOptions} from '@tanstack/react-query'

import type {EmbeddedData} from '../embedded-data-types'
import {type QueryDepsFn, QueryRouteQueryType} from './data-router-types'
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

type JsonResponse = {
  meta: EmbeddedData['meta']
  payload: Record<string, unknown>
}
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
  type: typeof QueryRouteQueryType.Blocking
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
    queryDeps: ({pathname}) => ({pathname}),
    queryFn: async ({routeId, queryDeps}) => {
      // Merge the appTypeHeader into any existing headers in queryDeps.init, if present
      const appTypeHeader = getAppTypeHeader('dataRouter')
      const mergedQueryDeps = appTypeHeader
        ? {
            ...queryDeps,
            init: {
              ...queryDeps?.init,
              headers: {...appTypeHeader, ...queryDeps?.init?.headers},
            },
          }
        : queryDeps

      const json = await queryFnFetch<JsonResponse>({
        queryDeps: mergedQueryDeps,
      })
      return responseJsonToQueryData(json, routeId)
    },
    type: QueryRouteQueryType.Blocking,
    select: data => selectDataFromQueryData(data),
    ...opts,
  }
}

function responseJsonToQueryData<Res>(json: JsonResponse, routeId: string): Res {
  const routePayload = json.payload?.[routeId]
  if (!routePayload) {
    throw new Error(`Unable to find payload for route Id: ${routeId}`)
  }

  return {
    meta: json.meta,
    payload: routePayload,
  } as Res
}

function selectDataFromQueryData<Res>(data: unknown): Res {
  const typedData = data as JsonResponse

  return typedData.payload as Res
}
