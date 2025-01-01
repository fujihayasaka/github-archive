import type {QueryMeta, queryOptions} from '@tanstack/react-query'
import type {Params, PathParam} from 'react-router-dom'

export const QueryRouteQueryType = {
  /**
   * A blocking query will resolve _prior to navigation_
   */
  Blocking: 'Blocking',
  /**
   * A Deferred query will begin during navigation, but may resolve after navigation completes
   */
  Deferred: 'Deferred',
} as const
export type QueryRouteQueryType = (typeof QueryRouteQueryType)[keyof typeof QueryRouteQueryType]

export type ComponentRenderingProperties =
  | 'Component'
  | 'ErrorBoundary'
  | 'HydrateFallback'
  | 'children'
  | 'element'
  | 'hydrateFallbackElement'

export type QueryDepsFn<RoutePath extends string> = (args: {
  pathname: string
  params: NonNullableType<Params<PathParam<RoutePath>>>
  searchParams: URLSearchParams
}) => unknown

export type QueryRouteQueryConfig<
  AppName extends string,
  RouteId extends string,
  RoutePath extends string,
  Name extends string,
  Deps extends QueryDepsFn<RoutePath> | undefined,
  Res,
  Type extends QueryRouteQueryType,
> = Omit<Parameters<typeof queryOptions>[0], 'queryFn' | 'queryKey'> & {
  queryName: Name
  /**
   * QueryDeps is an optional function that defines which parts of a page view the `queryFn` relies on.
   */
  queryDeps?: Deps
  /**
   * The queryFn to call.
   * This accepts dependencies returned from the queryDeps function if one exists and returns a response to cache.
   */
  queryFn: (
    queryKey: {
      appName: AppName
      routeId: RouteId
      routePath: RoutePath
      queryName: Name
      queryDeps: Deps extends QueryDepsFn<RoutePath> ? ReturnType<Deps> : Record<string, never>
    },
    opts: {signal: AbortSignal; meta: QueryMeta | undefined},
  ) => Res // The argument type of `queryFn` is tied to `queryDeps`
  /**
   * The {@link QueryRouteQueryType} type of query to initiate
   */
  type?: Type

  /**
   * A staleTime override for navigation
   * When this is configured, navigation staleTimes can be controlled separately
   * from rendering staleTimes
   * @default 200
   */
  staleTimeForNavigation?: number
}

export type NonNullableType<Original extends object> = {
  [K in keyof Original]: NonNullable<Original[K]>
}
