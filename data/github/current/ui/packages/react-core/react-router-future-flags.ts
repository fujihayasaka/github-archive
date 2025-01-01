/**
 * React Router uses "future flags" to introduce breaking changes in a backwards-compatible way.
 *
 * > React Router is foundational to your application. We want to make make sure that upgrading to new major
 * > versions is as smooth as possible while still allowing us to adjust and enhance the behavior and API as the React ecosystem advances.
 *
 * See https://reactrouter.com/6.28.0/upgrading/future
 */

/**
 * Future flags used by `Router` or `createRouter` to prepare for ReactRouter v7
 * See https://reactrouter.com/6.28.0/upgrading/future
 */
export const v7_routerFutureFlags = {
  v7_fetcherPersist: true,
  v7_normalizeFormMethod: true,
  v7_partialHydration: true,
  v7_relativeSplatPath: true,
  v7_skipActionErrorRevalidation: true,
} as const

/**
 * Future flags used by `Router` or `RouteProvider` to prepare for ReactRouter v7
 * See https://reactrouter.com/6.28.0/upgrading/future
 */
export const v7_routeProviderFutureFlags = {
  v7_startTransition: true,
} as const
