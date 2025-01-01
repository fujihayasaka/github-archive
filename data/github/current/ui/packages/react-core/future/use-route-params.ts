import type {Params, PathParam} from 'react-router-dom'

import type {QueryRouteQueryConfig, QueryRouteQueryType} from './data-router-types'
import {type QueryRoute, useRouteMatches} from './query-route'

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
  const matches = useRouteMatches()

  const match = matches.find(m => m.id === route.id)
  if (!match) {
    const validRouteIds = matches.map(m => m.id).join(', ')
    throw new Error(
      `Cannot read params from unmounted route with ID "${route.id}". Mounted route IDs are: "${validRouteIds}"`,
    )
  }

  return match.params as Params<PathParam<Config['path']>>
}
