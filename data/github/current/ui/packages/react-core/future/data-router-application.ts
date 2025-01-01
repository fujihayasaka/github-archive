import type {RouteObject} from 'react-router-dom'

import type {AppRegistration} from '../app-routing-types'
import type {EmbeddedData} from '../embedded-data-types'
import type {QueryDepsFn, QueryRouteQueryConfig, QueryRouteQueryType} from './data-router-types'
import {QueryRoute} from './query-route'

export type GetRoutesFunction = (args: {isEnabled: (featureName: string) => boolean | undefined}) => RouteObject[]

interface DataRouterAppRegistration extends AppRegistration {
  App?: never
  routes: RouteObject[]
}

export class DataRouterApplication<T extends string> {
  declare readonly name: T
  #routesOrGetRoutes: RouteObject[] | GetRoutesFunction
  embeddedData?: EmbeddedData

  constructor(name: T, routesOrGetRoutes: RouteObject[] | GetRoutesFunction) {
    this.name = name
    this.#routesOrGetRoutes = routesOrGetRoutes
    this.registration = this.registration.bind(this)
  }

  registration(opts?: {embeddedData?: EmbeddedData}): DataRouterAppRegistration {
    this.embeddedData = opts?.embeddedData
    const routes = this.getRoutes()
    return {
      routes,
    }
  }

  private getRoutes() {
    if (typeof this.#routesOrGetRoutes === 'function') {
      const isEnabled = (featureName: string) => {
        const enabledFeatures = this.embeddedData?.appPayload?.enabled_features as Record<string, boolean> | undefined
        if (!enabledFeatures || !(featureName in enabledFeatures)) {
          return undefined
        }
        return enabledFeatures[featureName]
      }
      return this.#routesOrGetRoutes({isEnabled})
    }
    return this.#routesOrGetRoutes
  }
}

const MAX_DEFINED_QUERIES_COUNT = 4

// NOTE: if this classname changes from `DataRouterApplicationBuilder`, also update the react-app-name ESLint rule
// /ui/packages/eslint-plugin-github-monorepo/rules/react-app-name.js
export class DataRouterApplicationBuilder<T extends string> {
  // NOTE: if this method name changes from `create`, also update the react-app-name ESLint rule
  // /ui/packages/eslint-plugin-github-monorepo/rules/react-app-name.js
  static create<T extends string>(name: T) {
    return new DataRouterApplicationBuilder<T>(name)
  }

  declare readonly name: T
  #app?: DataRouterApplication<T>

  private constructor(name: T) {
    this.name = name
  }

  getEmbeddedData = () => {
    if (!this.#app) {
      throw new Error('getEmbeddedData should only be called after createDataRouterAppFromRoutes')
    }
    return this.#app.embeddedData
  }

  createDataRouterAppFromRoutes(routes: RouteObject[] | GetRoutesFunction) {
    this.#app = new DataRouterApplication(this.name, routes)
    return this.#app
  }

  // #region createQueryRouteConfig

  /**
   * createQueryRouteConfig is a complicated method that takes a variadic list of 'queries'
   * and converts them to a keyed object of queries, while also implementing a few additional
   * methods on the RouteConfig
   *
   * We have to defined a separate function header for _every query length_ in the tuple of queries
   * _yes, this is unideal_
   * but this is necessary to have typescript correctly handle inferring of all types across each of the
   * possible queries and merging them together for the output RouteConfig object.
   *
   * If you have a Route with more queries than we have defined here, you may need to extend the types to accommodate
   * that new entry! Reach out if you need help with this!
   *
   * {@see https://github.com/github/github/pull/357701} For a sample PR for adding to the accepted list of query configs
   */

  /**
   * With no defined queries
   */
  createQueryRouteConfig<AppName extends string, RouteId extends string, RoutePath extends string>(
    /** RouteId must be a valid JavaScript camelCase Identifier */
    id: RouteId,
    args: {
      path: RoutePath
      index?: boolean
      queries?: []
    },
  ): QueryRoute<AppName, RouteId, RoutePath, {}>
  /**
   * With 1 defined query
   */
  createQueryRouteConfig<
    AppName extends string,
    RouteId extends string,
    RoutePath extends string,
    /** Query 1 */
    Query1Name extends string,
    Query1Deps extends QueryDepsFn<RoutePath>,
    Query1Res,
    Query1Type extends QueryRouteQueryType,
  >(
    /** RouteId must be a valid JavaScript camelCase Identifier */
    id: RouteId,
    args: {
      path: RoutePath
      index?: boolean
      queries: [QueryRouteQueryConfig<AppName, string, RoutePath, Query1Name, Query1Deps, Query1Res, Query1Type>]
    },
  ): QueryRoute<
    AppName,
    RouteId,
    RoutePath,
    {
      [K in Query1Name]: QueryRouteQueryConfig<
        AppName,
        RouteId,
        RoutePath,
        Query1Name,
        Query1Deps,
        Query1Res,
        Query1Type
      >
    }
  >

  /**
   * With 2 defined queries
   */
  createQueryRouteConfig<
    AppName extends string,
    RouteId extends string,
    RoutePath extends string,
    /** Query 1 */
    Query1Name extends string,
    Query1Deps extends QueryDepsFn<RoutePath>,
    Query1Res,
    Query1Type extends QueryRouteQueryType,
    /** Query 2 */
    Query2Name extends string,
    Query2Deps extends QueryDepsFn<RoutePath>,
    Query2Res,
    Query2Type extends QueryRouteQueryType,
  >(
    /** RouteId must be a valid JavaScript camelCase Identifier */
    id: RouteId,
    args: {
      path: RoutePath
      index?: boolean
      queries: [
        QueryRouteQueryConfig<AppName, string, RoutePath, Query1Name, Query1Deps, Query1Res, Query1Type>,
        QueryRouteQueryConfig<AppName, string, RoutePath, Query2Name, Query2Deps, Query2Res, Query2Type>,
      ]
    },
  ): QueryRoute<
    AppName,
    RouteId,
    RoutePath,
    {
      [K in Query1Name]: QueryRouteQueryConfig<
        AppName,
        RouteId,
        RoutePath,
        Query1Name,
        Query1Deps,
        Query1Res,
        Query1Type
      >
    } & {
      [K in Query2Name]: QueryRouteQueryConfig<
        AppName,
        RouteId,
        RoutePath,
        Query2Name,
        Query2Deps,
        Query2Res,
        Query2Type
      >
    }
  >

  /**
   * With 3 defined queries
   */
  createQueryRouteConfig<
    AppName extends string,
    RouteId extends string,
    RoutePath extends string,
    /** Query 1 */
    Query1Name extends string,
    Query1Deps extends QueryDepsFn<RoutePath>,
    Query1Res,
    Query1Type extends QueryRouteQueryType,
    /** Query 2 */
    Query2Name extends string,
    Query2Deps extends QueryDepsFn<RoutePath>,
    Query2Res,
    Query2Type extends QueryRouteQueryType,
    /** Query 3 */
    Query3Name extends string,
    Query3Deps extends QueryDepsFn<RoutePath>,
    Query3Res,
    Query3Type extends QueryRouteQueryType,
  >(
    /** RouteId must be a valid JavaScript camelCase Identifier */
    id: RouteId,
    args: {
      path: RoutePath
      index?: boolean
      queries: [
        QueryRouteQueryConfig<AppName, string, RoutePath, Query1Name, Query1Deps, Query1Res, Query1Type>,
        QueryRouteQueryConfig<AppName, string, RoutePath, Query2Name, Query2Deps, Query2Res, Query2Type>,
        QueryRouteQueryConfig<AppName, string, RoutePath, Query3Name, Query3Deps, Query3Res, Query3Type>,
      ]
    },
  ): QueryRoute<
    AppName,
    RouteId,
    RoutePath,
    {
      [K in Query1Name]: QueryRouteQueryConfig<
        AppName,
        RouteId,
        RoutePath,
        Query1Name,
        Query1Deps,
        Query1Res,
        Query1Type
      >
    } & {
      [K in Query2Name]: QueryRouteQueryConfig<
        AppName,
        RouteId,
        RoutePath,
        Query2Name,
        Query2Deps,
        Query2Res,
        Query2Type
      >
    } & {
      [K in Query3Name]: QueryRouteQueryConfig<
        AppName,
        RouteId,
        RoutePath,
        Query3Name,
        Query3Deps,
        Query3Res,
        Query3Type
      >
    }
  >

  /**
   * With 4 defined queries
   */
  createQueryRouteConfig<
    AppName extends string,
    RouteId extends string,
    RoutePath extends string,
    /** Query 1 */
    Query1Name extends string,
    Query1Deps extends QueryDepsFn<RoutePath>,
    Query1Res,
    Query1Type extends QueryRouteQueryType,
    /** Query 2 */
    Query2Name extends string,
    Query2Deps extends QueryDepsFn<RoutePath>,
    Query2Res,
    Query2Type extends QueryRouteQueryType,
    /** Query 3 */
    Query3Name extends string,
    Query3Deps extends QueryDepsFn<RoutePath>,
    Query3Res,
    Query3Type extends QueryRouteQueryType,
    /** Query 4 */
    Query4Name extends string,
    Query4Deps extends QueryDepsFn<RoutePath>,
    Query4Res,
    Query4Type extends QueryRouteQueryType,
  >(
    /** RouteId must be a valid JavaScript camelCase Identifier */
    id: RouteId,
    args: {
      path: RoutePath
      index?: boolean
      queries: [
        QueryRouteQueryConfig<AppName, string, RoutePath, Query1Name, Query1Deps, Query1Res, Query1Type>,
        QueryRouteQueryConfig<AppName, string, RoutePath, Query2Name, Query2Deps, Query2Res, Query2Type>,
        QueryRouteQueryConfig<AppName, string, RoutePath, Query3Name, Query3Deps, Query3Res, Query3Type>,
        QueryRouteQueryConfig<AppName, string, RoutePath, Query4Name, Query4Deps, Query4Res, Query4Type>,
      ]
    },
  ): QueryRoute<
    AppName,
    RouteId,
    RoutePath,
    {
      [K in Query1Name]: QueryRouteQueryConfig<
        AppName,
        RouteId,
        RoutePath,
        Query1Name,
        Query1Deps,
        Query1Res,
        Query1Type
      >
    } & {
      [K in Query2Name]: QueryRouteQueryConfig<
        AppName,
        RouteId,
        RoutePath,
        Query2Name,
        Query2Deps,
        Query2Res,
        Query2Type
      >
    } & {
      [K in Query3Name]: QueryRouteQueryConfig<
        AppName,
        RouteId,
        RoutePath,
        Query3Name,
        Query3Deps,
        Query3Res,
        Query3Type
      >
    } & {
      [K in Query4Name]: QueryRouteQueryConfig<
        AppName,
        RouteId,
        RoutePath,
        Query4Name,
        Query4Deps,
        Query4Res,
        Query4Type
      >
    }
  >

  /**
   * Implementation
   */
  createQueryRouteConfig<RouteId extends string, RoutePath extends string>(
    /** RouteId must be a valid JavaScript camelCase Identifier */
    id: RouteId,
    {
      path,
      index,
      queries = [],
    }: {
      path: RoutePath
      index?: boolean
      queries?:
        | []
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        | [QueryRouteQueryConfig<any, any, any, any, any, any, any>]
        | [
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            QueryRouteQueryConfig<any, any, any, any, any, any, any>,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            QueryRouteQueryConfig<any, any, any, any, any, any, any>,
          ]
        | [
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            QueryRouteQueryConfig<any, any, any, any, any, any, any>,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            QueryRouteQueryConfig<any, any, any, any, any, any, any>,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            QueryRouteQueryConfig<any, any, any, any, any, any, any>,
          ]
        | [
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            QueryRouteQueryConfig<any, any, any, any, any, any, any>,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            QueryRouteQueryConfig<any, any, any, any, any, any, any>,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            QueryRouteQueryConfig<any, any, any, any, any, any, any>,
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            QueryRouteQueryConfig<any, any, any, any, any, any, any>,
          ]
    },
  ) {
    assertQueriesWithinLimit(queries)
    assertCamelCase(id)

    return new QueryRoute({
      appName: this.name,
      id,
      path,
      queries: toKeyedQueries(queries),
      index: index ?? false,
      getEmbeddedData: this.getEmbeddedData,
    })
  }

  // #endregion createQueryRouteConfig
}

function assertQueriesWithinLimit<T>(arr: T[]) {
  if (arr.length > MAX_DEFINED_QUERIES_COUNT) throw new InvalidNumberOfQueryConfigsError(arr.length)
}

class DuplicateRouteQueryNameError extends Error {
  constructor(queryName: string) {
    super(`query names cannot be duplicated: \`${queryName}\` has already been defined for this route.`)
    this.name = 'DuplicateRouteQueryNameError'
  }
}

function toKeyedQueries<
  T extends
    | []
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    | [QueryRouteQueryConfig<any, any, any, any, any, any, any>]
    | [
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        QueryRouteQueryConfig<any, any, any, any, any, any, any>,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        QueryRouteQueryConfig<any, any, any, any, any, any, any>,
      ]
    | [
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        QueryRouteQueryConfig<any, any, any, any, any, any, any>,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        QueryRouteQueryConfig<any, any, any, any, any, any, any>,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        QueryRouteQueryConfig<any, any, any, any, any, any, any>,
      ]
    | [
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        QueryRouteQueryConfig<any, any, any, any, any, any, any>,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        QueryRouteQueryConfig<any, any, any, any, any, any, any>,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        QueryRouteQueryConfig<any, any, any, any, any, any, any>,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        QueryRouteQueryConfig<any, any, any, any, any, any, any>,
      ],
>(queries: T) {
  const registeredQueryNames = new Set<string>()

  return Object.fromEntries(
    queries.map(({queryName, ...config}) => {
      if (registeredQueryNames.has(queryName)) {
        throw new DuplicateRouteQueryNameError(queryName)
      }
      registeredQueryNames.add(queryName)
      return [queryName, config] as const
    }),
  )
}

class InvalidNumberOfQueryConfigsError extends Error {
  constructor(queriesLength: number) {
    super(
      `Invalid number of query configs error. ${queriesLength} queries supplied of a max ${MAX_DEFINED_QUERIES_COUNT} queries allowed.`,
    )
    this.name = 'InvalidNumberOfQueryConfigsError'
  }
}

function assertCamelCase(str: string) {
  // Regular expression to validate camel case
  const camelCasePattern = /^[a-z][a-zA-Z0-9]*$/
  if (!camelCasePattern.test(str)) throw new InvalidIdentifierError(str)
}

export class InvalidIdentifierError extends Error {
  constructor(str: string) {
    super(`\`${str}\` must be camel cased`)
    this.name = 'InvalidIdentifierError'
  }
}
