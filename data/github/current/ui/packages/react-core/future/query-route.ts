import {startSoftNav} from '@github-ui/soft-nav/state'
import {IS_BROWSER, ssrSafeLocation} from '@github-ui/ssr-utils'
import {queryOptions, type SkipToken, type UseQueryOptions} from '@tanstack/react-query'
import {
  createPath,
  generatePath,
  type LoaderFunction,
  type Params,
  type PathParam,
  type RouteObject,
  type UIMatch,
  useMatches,
} from 'react-router-dom'

import type {EmbeddedData} from '../embedded-data-types'
import {getQueryClient} from '../query-client'
import {makeQueryKey, type RouteQueryKey} from '../query-key'
import {
  type ComponentRenderingProperties,
  type QueryDepsFn,
  type QueryRouteQueryConfig,
  QueryRouteQueryType,
} from './data-router-types'
import {wrapWithProfiler} from './WrapWithProfiler'

type QueryOptions = Omit<Parameters<typeof queryOptions>[0], 'queryFn' | 'queryKey'>

type GetEmbeddedDataFn = () => EmbeddedData | undefined

export type QueryOptionsWithKey = UseQueryOptions<unknown, Error, unknown> & {
  initialData?: unknown
} & {
  queryKey: RouteQueryKey
  queryFn: Exclude<UseQueryOptions<unknown, Error, unknown>['queryFn'], SkipToken>
}

export type RouteMatches = Array<
  UIMatch<null | {
    route: QueryRoute<
      string,
      string,
      string,
      Record<
        string,
        QueryRouteQueryConfig<string, string, string, string, QueryDepsFn<string>, string, QueryRouteQueryType>
      >
    >
    queries: Record<string, {type: QueryRouteQueryType; queryConfig: QueryOptionsWithKey}>
  }>
>

export function useRouteMatches() {
  return useMatches() as RouteMatches
}

const QUERY_ROUTE_QUERY_CLIENT_DEFAULTS: QueryOptions = {
  refetchOnWindowFocus: false,
  retry: false,
  networkMode: 'always',
  staleTime: 1000 * 60 * 60 * 24, // 1 day in ms
}

export const DEFAULT_STALE_TIME_FOR_NAVIGATION = 200

/**
 * the 'http' request is the same object sent to every nested loader.
 * We can store it and only `startSoftNav` on the first call, instead of on
 * every loader call.
 *
 * The `WeakSet` will release the object after the request completes, so we don't need to
 * worry about cleaning it up manually.
 */
const requestsInitiatedSoftNav = new WeakSet<Request>()
function startSoftNavOncePerRequestInstance(request: Request) {
  if (IS_BROWSER) {
    if (!requestsInitiatedSoftNav.has(request)) {
      startSoftNav('react')
      requestsInitiatedSoftNav.add(request)
    }
  }
}
export class QueryRoute<
  AppName extends string,
  RouteId extends string,
  RoutePath extends string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  Queries extends Record<string, QueryRouteQueryConfig<AppName, RouteId, RoutePath, any, any, any, any>>,
> {
  #appName: AppName
  #getEmbeddedData: GetEmbeddedDataFn

  id: RouteId
  path: RoutePath
  queries: Queries
  index: boolean

  constructor(args: {
    appName: AppName
    id: RouteId
    path: RoutePath
    queries: Queries
    index: boolean
    getEmbeddedData: GetEmbeddedDataFn
  }) {
    this.#appName = args.appName
    this.id = args.id
    this.path = args.path
    this.queries = args.queries
    this.index = args.index
    this.#getEmbeddedData = args.getEmbeddedData
  }

  /**
   * Validates whether an argument is the same as the route
   *
   * We don't want to do a pure equality check like `Object.is` since on hydration
   * we might have different/similar objects.
   *
   * Doing a simple `id === id` check since this is most commonly going to catch issues
   * should there be any without doing a real deepEquality check
   */
  isSameRoute(route: unknown): route is QueryRoute<AppName, RouteId, RoutePath, Queries> {
    return Boolean(
      typeof route === 'object' && route && 'id' in route && typeof route.id === 'string' && route.id === this.id,
    )
  }

  /**
   * Given a params object generates a valid pathname for the route.
   * Optionally search parameters and/or a hash can be passed.
   */
  generatePath(
    params: {[key in PathParam<RoutePath>]: string},
    args?: {
      search?: ConstructorParameters<typeof URLSearchParams>[0]
      hash?: string
    },
  ) {
    return createPath({
      pathname: generatePath(this.path, params),
      search: args?.search ? new URLSearchParams(args.search).toString() : undefined,
      hash: args?.hash,
    })
  }

  #initializeQueryFromEmbeddedData(queryName: keyof Queries, queryKey: ReturnType<typeof queryOptions>['queryKey']) {
    const queryClient = getQueryClient()
    const embeddedData = this.#getEmbeddedData()
    const embeddedDataPayload = embeddedData?.payload as Record<string, Record<keyof Queries, unknown>> | undefined
    const initialData = this.#buildInitialDataForQueryClient(embeddedData, queryName)

    // Note that embedded data is not keyed by `queryDeps`, so it could be applied to any query with the same
    // `routeId` and `queryName`.
    // Because of this, we only want it to apply on initial render, so we delete it after first access.
    if (initialData) {
      if (queryName === 'mainQuery') {
        delete embeddedDataPayload?.[this.id]
      } else {
        delete embeddedDataPayload?.[this.id]?.[queryName]
      }

      queryClient.setQueryData<typeof initialData>(queryKey, initialData)
    }
  }

  /**
   * The react-route compatible loader. This loops through each query defined on the route,
   * fetching or prefetching the data as necessary.
   */
  #loader: LoaderFunction = async ({request, params}) => {
    startSoftNavOncePerRequestInstance(request)
    const blockingRequests: Array<Promise<unknown>> = []
    const {searchParams} = new URL(request.url, ssrSafeLocation.origin)

    const pathname = toQualifiedPath(this.path, params)

    const queryClient = getQueryClient()

    const queryConfigs = objectEntries(this.queries).map(
      ([
        queryName,
        {
          queryFn,
          queryDeps,
          type = QueryRouteQueryType.Deferred,
          staleTimeForNavigation = DEFAULT_STALE_TIME_FOR_NAVIGATION,
          ...config
        },
      ]) => {
        const deps = queryDeps?.({pathname, params, searchParams}) ?? {}

        const queryKeyObj = {
          appName: this.#appName,
          routeId: this.id,
          routePath: this.path,
          queryName: queryName.toString(),
          queryDeps: deps,
        }

        const queryConfig = queryOptions({
          ...QUERY_ROUTE_QUERY_CLIENT_DEFAULTS,
          queryKey: makeQueryKey(queryKeyObj),
          queryFn: ({signal, meta}) => {
            return queryFn(queryKeyObj, {signal, meta})
          },
          ...(config as QueryOptions),
        })

        this.#initializeQueryFromEmbeddedData(queryName, queryConfig.queryKey)

        // Don't try to begin queries on the server
        if (IS_BROWSER) {
          const fetchConfig = {
            ...queryConfig,
            // during navigation we set the staletime very short to ensure fresh data is pulled, but not too aggressively as to get caught during hydration for a server hydrated query
            staleTime: staleTimeForNavigation,
          }
          switch (type) {
            case QueryRouteQueryType.Deferred: {
              /**
               * Deferred queries use prefetch to avoid throwing/rejecting on failure.
               * We initiate these requests during navigation, but we don't await them, so they
               * can resolve anytime between now and well after navigation completes.
               */
              void queryClient.prefetchQuery(fetchConfig)
              break
            }
            case QueryRouteQueryType.Blocking: {
              /**
               * Immediately returns stale data if it exists, but fetches updates in the background
               * this gives us a default `stale-while-revalidate` behavior.
               *
               * We may later make this configureable with a `blockingQueryBehavior` of `stale-while-revalidate` or `revalidate`
               */
              const query = queryClient.ensureQueryData({...fetchConfig, revalidateIfStale: true})
              blockingRequests.push(query)
              break
            }
            default: {
              throw new Error(
                `Invalid QueryRouteQueryType defined, \`${type}\`. Valid QueryRouteQueryTypes are ${JSON.stringify(
                  Object.keys(QueryRouteQueryType),
                )}`,
              )
            }
          }
        }

        return [queryName, {queryConfig, type}] as const
      },
    )

    await Promise.all(blockingRequests)

    return {
      route: this,
      queries: Object.fromEntries(queryConfigs),
    }
  }

  /**
   * Given components and children to render, returns a react-router compatible route
   * definition implementing the `QueryRoute` logic.
   */
  toRoute = ({Component, element, ...args}: Pick<RouteObject, ComponentRenderingProperties>): RouteObject => {
    if (this.index) {
      return {
        ...args,
        id: this.id,
        children: undefined,
        path: this.path,
        index: this.index,
        loader: this.#loader,
        element: wrapWithProfiler(this.id, {element, Component}),
      }
    }

    return {
      ...args,
      id: this.id,
      path: this.path,
      index: this.index,
      loader: this.#loader,
      element: wrapWithProfiler(this.id, {element, Component}),
    }
  }

  #buildInitialDataForQueryClient(embeddedData: EmbeddedData | undefined, queryName: keyof Queries) {
    // embedded data is keyed by `embeddedData.payload[routeId][queryName]`
    const embeddedDataPayload = embeddedData?.payload as Record<string, Record<keyof Queries, unknown>> | undefined
    const routePayload = embeddedDataPayload?.[this.id]

    if (!routePayload) {
      return
    }

    if (queryName !== 'mainQuery') {
      return routePayload?.[queryName]
    }

    const embeddedDataTitle = embeddedData?.title || embeddedData?.meta?.title

    return {
      meta: embeddedDataTitle ? {title: embeddedDataTitle} : undefined,
      payload: routePayload,
    }
  }
}

/**
 * Given a `routePath` path pattern and a loader-like params object return a
 * string with the params replacing the pattern
 */
function toQualifiedPath<RoutePath extends string>(routePath: RoutePath, params: Params<PathParam<RoutePath>>) {
  return generatePath(routePath, translateUndefinedToNull(params))
}

/**
 * Given an object with potentially undefined parameters map those to `null`
 *
 * This is mostly useful for mapping an object from a loader params shape
 * to a generatePath params shape
 */
function translateUndefinedToNull<T extends Record<string, string | undefined>>(
  input: T,
): {
  [K in keyof T]: T[K] extends undefined | null ? null : NonNullable<T[K]>
} {
  return Object.fromEntries(
    objectEntries(input).map(([key, value]) => [key, value === undefined ? null : value] as const),
  ) as {
    [K in keyof T]: T[K] extends undefined | null ? null : NonNullable<T[K]>
  }
}

/**
 * A small type-safe wrapper around `Object.entries`
 *
 * By default, typescript makes the entries keys `string` typed only (as it does for Object.keys)
 * this assumes a bit more stable structure around the entries
 */
const objectEntries = <T extends object>(obj: T) => {
  return Object.entries(obj) as Array<[keyof typeof obj, (typeof obj)[keyof typeof obj]]>
}
