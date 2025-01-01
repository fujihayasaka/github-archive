import {useParams, type Params, type PathParam} from 'react-router-dom'
import {useQueriesConfigs} from './use-route-query'
import type {NonNullableType, QueryRouteQueryConfig, QueryRouteQueryType} from './data-router-types'
import type {QueryRoute} from './query-route'

/**
 * Using a route, return the valid params for that route, typed
 */
export function useRouteParams<
  Config extends QueryRoute<
    string,
    string,
    string,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    Record<string, QueryRouteQueryConfig<string, any, any, any, any, any, QueryRouteQueryType>>
  >,
>(route: Config) {
  useQueriesConfigs(route)
  /**
   * React router has these as nullable, for the case where it's called incorrectly, but we should throw
   * on those cases already and therefor can cast this a bit more tightly
   */
  return useParams<PathParam<Config['path']>>() as NonNullableType<Params<PathParam<Config['path']>>>
}
