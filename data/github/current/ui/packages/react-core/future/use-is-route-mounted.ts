import {type QueryRoute, useRouteMatches} from './query-route'

/**
 * This function checks the current route matches to see if the provided
 * query route is active.
 */
export function useIsRouteMounted(route: QueryRoute<string, string, string, {}>) {
  const routeMatches = useRouteMatches()
  return !!routeMatches.find(routeMatch => routeMatch.id === route.id)
}
