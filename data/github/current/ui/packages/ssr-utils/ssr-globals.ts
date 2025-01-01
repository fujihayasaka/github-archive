// When using SSR, browser globals are not available. If you try to use them, Node.js will throw an error
type SSRSafeLocation = Pick<Location, 'pathname' | 'origin' | 'search' | 'hash' | 'href'>

// In some cases, we want to force the server environment to be used in the browser. This is useful for testing/profiling
const forceServer = typeof FORCE_SERVER_ENV !== 'undefined' ? FORCE_SERVER_ENV : false

// eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
export const ssrSafeDocument = typeof document === 'undefined' || forceServer ? undefined : document
// eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
export const ssrSafeWindow = typeof window === 'undefined' || forceServer ? undefined : window
// eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
export const ssrSafeHistory = typeof history === 'undefined' || forceServer ? undefined : history

export const ssrSafeLocation: SSRSafeLocation =
  // eslint-disable-next-line ssr-friendly/no-dom-globals-in-module-scope
  typeof location === 'undefined' || forceServer ? {pathname: '', origin: '', search: '', hash: '', href: ''} : location

export function setLocation(url: string) {
  // eslint-disable-next-line no-restricted-syntax
  const parsedURL: SSRSafeLocation = new URL(url)
  const {pathname, origin, search, hash} = parsedURL

  Object.assign(ssrSafeLocation, {pathname, origin, search, hash})
}
