import type React from 'react'
import type {Params, PathParam} from 'react-router-dom'
import type {ConcreteRequest, OperationType, PreloadableConcreteRequest, Variables, VariablesOf} from 'relay-runtime'

import type {EntryPoint, EntryPointComponent, Environment} from 'react-relay'

import type {ErrorCallbacks} from '@github-ui/fetch-graphql'
import type {TransitionType} from '@github-ui/react-core/app-routing-types'

export type RouteParams<Segments extends string> = {
  pathParams: Params<Segments>
  searchParams: URLSearchParams
}

// Arbitrarily transform variable values.  Scoped to a route
// Each route should have a matching transformer implemented in the server
export type VariableTransformer<Segments extends string> = (
  variables: Variables,
  routeParams: RouteParams<Segments>,
  environment?: Environment,
) => Variables

export type RelayRouteProps<
  Path extends string,
  PreloadedQueryProps extends Record<string, OperationType>,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  PreloadedEntryPoints extends Record<string, EntryPoint<any, any> | undefined>,
  RuntimeProps extends NonNullable<unknown>,
  ExtraProps extends NonNullable<unknown>,
> = {
  path: Path
  /**
   * A string that identifies the component this route renders to Relay. By default
   * we infer this from the `displayName` of the `component`. You probably don't need
   * to set this manually.
   */
  resourceName?: string
  componentLoader: () => Promise<
    EntryPointComponent<PreloadedQueryProps, PreloadedEntryPoints, RuntimeProps, ExtraProps>
  >
  Component?: EntryPointComponent<PreloadedQueryProps, PreloadedEntryPoints, RuntimeProps, ExtraProps>
  queryConfigs: QueryConfigs<Path, PreloadedQueryProps>
  transformVariables?: VariableTransformer<PathParam<Path>>
  /**
   * The title of the page. Currently there is no mechanism to have a title vary based on the route params or loaded
   * data.
   */
  title: string
  relayEnvironment: Environment
  fallback: React.ReactNode

  /**
   * If a preloaded query has a 'timestamp' field and it's value is smaller than the current (UTC) time by more than
   * `maxAge`, we ignore the preloaded data and instead fetch the data from the server
   */
  maxAge?: number
  errorCallbacks?: ErrorCallbacks
  transitionType?: TransitionType
}

export type QueryConfigs<Path extends string, PreloadedQueryProps extends Record<string, OperationType>> = {
  /**
   * For each query in {@link PreloadedQueryProps} map that query, by name
   * to an object container a reference to the {@link ConcreteRequest}
   * and a set of variableMappers that map each variable based on the
   * path and search parameters (collectively called {@link RouteParams})
   */
  [PreloadedQueryKey in keyof PreloadedQueryProps]: {
    concreteRequest: ConcreteRequest | PreloadableConcreteRequest<OperationType>
    /**
     * Takes a {@link RouteParams} object an argument and returns a map of variables for use in the query
     * If any variable is mapped to undefined, the query itself becomes undefined.
     * and is filtered by `filterQueries`
     * `null` can be used to represent a variable with no value
     */
    variableMappers?: (
      routeParams: RouteParams<PathParam<Path>>,
      environment: Environment,
    ) => {
      /**
       * For Each variable defined in the preloaded query, map that variable
       * to a function that accepts path and search params as a {@link RouteParams}
       * object and returns a type that matches that variables type (or undefined)
       *
       * When a mapper returns undefined, the query is not run
       */
      [Var in keyof VariablesOf<PreloadedQueryProps[PreloadedQueryKey]>]:
        | VariablesOf<PreloadedQueryProps[PreloadedQueryKey]>[Var]
        | undefined
    }
  }
}

export type VariableMappers<
  Path extends string,
  PreloadedQueryProps extends Record<string, OperationType>,
> = QueryConfigs<Path, PreloadedQueryProps>[string]['variableMappers']
