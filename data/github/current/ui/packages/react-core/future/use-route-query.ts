import {
  type DefinedUseQueryResult,
  useQuery,
  type UseQueryOptions,
  type UseQueryResult,
  useSuspenseQuery,
  type UseSuspenseQueryOptions,
  type UseSuspenseQueryResult,
} from '@tanstack/react-query'
import {useLoaderData, useRouteLoaderData} from 'react-router-dom'

import type {RouteQueryKey} from '../query-key'
import type {QueryRouteQueryConfig, QueryRouteQueryType} from './data-router-types'
import {type QueryOptionsWithKey, type QueryRoute, useRouteMatches} from './query-route'

type UseQueriesConfigOptions = {
  allowReadFromChildRoutes?: boolean
}
/**
 * Returns the query configurations for a given route.
 * If called from the wrong route, throws an error.
 */
export function useQueriesConfigs<
  Config extends QueryRoute<
    string,
    string,
    string,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    Record<string, QueryRouteQueryConfig<string, any, any, any, any, any, QueryRouteQueryType>>
  >,
>(
  routeArg: Config,
  {allowReadFromChildRoutes}: UseQueriesConfigOptions = {},
): Record<keyof Config['queries'], {type: QueryRouteQueryType; queryConfig: QueryOptionsWithKey}> {
  type RouteData = {
    route: Config
    queries: Record<keyof Config['queries'], {type: QueryRouteQueryType; queryConfig: QueryOptionsWithKey}>
  }
  const matches = useRouteMatches()
  const argRouteIndex = matches.findIndex(r => r.id === routeArg.id)
  if (argRouteIndex === -1) {
    const validRouteIds = matches.map(m => m.id).join(', ')
    throw new Error(
      `Cannot read data from unmounted route with ID "${routeArg.id}". Mounted route IDs are: ${validRouteIds}`,
    )
  }
  const {route: currentRoute} = useLoaderData() as RouteData
  const {queries} = useRouteLoaderData(routeArg.id) as RouteData

  const currentRouteIndex = matches.findIndex(r => r.id === currentRoute.id)
  if (!allowReadFromChildRoutes && argRouteIndex > currentRouteIndex) {
    const validRouteIds = matches.map(m => m.id).join(', ')
    throw new Error(
      `Cannot read data from child route with ID "${routeArg.id}" from parent route "${currentRoute.id}". Use { allowReadFromChildRoutes: true } option to enable this.  Mounted route IDs are: ${validRouteIds}`,
    )
  }

  return queries
}

/**
 * Returns a single query configuration by name
 */
export function useQueriesConfig<
  Config extends QueryRoute<
    string,
    string,
    string,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    Record<string, QueryRouteQueryConfig<string, any, any, any, any, any, QueryRouteQueryType>>
  >,
  QueryName extends string & keyof Config['queries'],
>(
  route: Config,
  queryName: QueryName,
  options?: UseQueriesConfigOptions,
): {type: QueryRouteQueryType; queryConfig: QueryOptionsWithKey} {
  const ctx = useQueriesConfigs(route, options)
  return ctx[queryName]
}

/**
 * Given a named route query and a route, returns the
 * result of calling useQuery on the generated route config.
 *
 * Overrides for query configuration can be optionally passed as a third argument
 *
 * When called on a blocking route, data is always defined.
 * When called on a deferred route, data is potentially undefined.
 */
export function useRouteQuery<
  Config extends QueryRoute<
    string,
    string,
    string,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    Record<string, QueryRouteQueryConfig<string, any, any, any, any, any, any>>
  >,
  QueryName extends string & keyof Config['queries'],
>(
  route: Config,
  queryName: QueryName,
  queryOverrides?: Omit<UseQueryOptions<ReturnType<Config['queries'][QueryName]['queryFn']>>, 'queryKey' | 'queryFn'>,
) {
  const {queryConfig} = useQueriesConfig(route, queryName)
  /**
   * If we have a deferred query we don't have initial data always defined, so it potentially
   * could render with `undefined`.  When we have a blocking query, the loader awaits the data
   * so it should never be undefined
   */
  return {
    ...useQuery(
      // @ts-expect-error not sure
      {...queryConfig, ...queryOverrides},
    ),
    queryKey: queryConfig.queryKey,
  } as unknown as UseRouteQueryResult<Config['queries'][QueryName]> & {
    queryKey: RouteQueryKey
  }
}

/**
 * Given a named route query and a route, returns the
 * result of calling useSuspenseQuery on the generated route config.
 *
 * Overrides for query configuration can be optionally passed as a third argument
 *
 * When called on a blocking route, data is always defined.
 * When called on a deferred route, data is potentially undefined.
 */
export function useSuspenseRouteQuery<
  Config extends QueryRoute<
    string,
    string,
    string,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    Record<string, QueryRouteQueryConfig<string, any, any, any, any, any, any>>
  >,
  QueryName extends string & keyof Config['queries'],
>(
  route: Config,
  queryName: QueryName,
  queryOverrides?: Omit<
    UseSuspenseQueryOptions<ReturnType<Config['queries'][QueryName]['queryFn']>>,
    'queryKey' | 'queryFn'
  >,
) {
  const {queryConfig} = useQueriesConfig(route, queryName)
  /**
   * If we have a deferred query we don't have initial data always defined, so it potentially
   * could render with `undefined`.  When we have a blocking query, the loader awaits the data
   * so it should never be undefined
   */
  return {
    ...useSuspenseQuery(
      // @ts-expect-error not sure
      {...queryConfig, ...queryOverrides},
    ),
    queryKey: queryConfig.queryKey,
  } as UseSuspenseQueryResult<Awaited<ReturnType<Config['queries'][QueryName]['queryFn']>>> & {
    queryKey: RouteQueryKey
  }
}

/**
 * Given a named route query and a route, returns the
 * result of calling useQuery on the generated route config.
 *
 * Should be used in scenarios where a parent route's component wants to access data from
 * a child route. The parent component is responsible for ensuring the child route is
 * currently active, otherwise an error will be thrown.
 *
 * Overrides for query configuration can be optionally passed as a third argument
 *
 * Data will always be undefined, as it is not known whether or not the child route
 * is rendered
 */
export function useChildRouteQuery<
  Config extends QueryRoute<
    string,
    string,
    string,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    Record<string, QueryRouteQueryConfig<string, any, any, any, any, any, any>>
  >,
  QueryName extends string & keyof Config['queries'],
>(
  route: Config,
  queryName: QueryName,
  queryOverrides?: Omit<UseQueryOptions<ReturnType<Config['queries'][QueryName]['queryFn']>>, 'queryKey' | 'queryFn'>,
) {
  const {queryConfig} = useQueriesConfig(route, queryName, {allowReadFromChildRoutes: true})
  /**
   * If we have a deferred query we don't have initial data always defined, so it potentially
   * could render with `undefined`.  When we have a blocking query, the loader awaits the data
   * so it should never be undefined
   */
  return {
    ...useQuery(
      // @ts-expect-error not sure
      {...queryConfig, ...queryOverrides},
    ),
    queryKey: queryConfig.queryKey,
  } as UseQueryResult<Awaited<ReturnType<Config['queries'][QueryName]['queryFn']>>> & {
    queryKey: RouteQueryKey
  }
}

/**
 * Given a named route query and a route, returns the
 * result of calling useSuspenseQuery on the generated route config.
 *
 * Should be used in scenarios where a parent route's component wants to access data from
 * a child route. The parent component is responsible for ensuring the child route is
 * currently active, otherwise an error will be thrown.
 *
 * Overrides for query configuration can be optionally passed as a third argument
 */
export function useSuspenseChildRouteQuery<
  Config extends QueryRoute<
    string,
    string,
    string,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    Record<string, QueryRouteQueryConfig<string, any, any, any, any, any, any>>
  >,
  QueryName extends string & keyof Config['queries'],
>(
  route: Config,
  queryName: QueryName,
  queryOverrides?: Omit<
    UseSuspenseQueryOptions<ReturnType<Config['queries'][QueryName]['queryFn']>>,
    'queryKey' | 'queryFn'
  >,
) {
  const {queryConfig} = useQueriesConfig(route, queryName, {allowReadFromChildRoutes: true})
  /**
   * If we have a deferred query we don't have initial data always defined, so it potentially
   * could render with `undefined`.  When we have a blocking query, the loader awaits the data
   * so it should never be undefined
   */
  return {
    ...useSuspenseQuery(
      // @ts-expect-error not sure
      {...queryConfig, ...queryOverrides},
    ),
    queryKey: queryConfig.queryKey,
  } as UseSuspenseQueryResult<Awaited<ReturnType<Config['queries'][QueryName]['queryFn']>>> & {
    queryKey: RouteQueryKey
  }
}
/**
 * This type returns a version of `UseQuery` that considers `initialData` as defined when we have a blocking query
 * otherwise assumes initialData was undefined for deferred queries
 *
 * It uses the return types of `useQuery` in each of these cases, however typescript can't easily infer this
 * for us because of how generic the responses from `useQueriesConfig` is.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type UseRouteQueryResult<Config extends QueryRouteQueryConfig<any, any, any, string, any, any, any>> = Config extends {
  type?: typeof QueryRouteQueryType.Blocking
}
  ? DefinedUseQueryResult<Awaited<ReturnType<Config['queryFn']>>>
  : UseQueryResult<Awaited<ReturnType<Config['queryFn']>>>
