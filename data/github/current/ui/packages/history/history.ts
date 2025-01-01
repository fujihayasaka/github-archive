// eslint-disable-next-line no-restricted-imports
import {ssrSafeHistory, ssrSafeLocation, ssrSafeWindow} from '@github-ui/ssr-utils'

type HistoryState = {
  // React Router's id for a route
  key?: string
  // ID of the current `<react-app>`, it can either be an uuid or `rails` if there is no app present. Used
  // to decide if Turbo should restore a page or not during back/forward navigation.
  appId?: string
  // DEPRECATED
  skipTurbo?: boolean
  // Used by `updatable-content`
  staleRecords?: {[key: string]: string}
  // Managed by Turbo, the restorationIdentifier is used to restore a page during back/forward navigation
  turbo?: {
    restorationIdentifier: string
  }
  // How many Turbo navigations happened in this session, used by the staffbar soft navigation label
  turboCount?: number
  // DEPRECATED
  usr?: {
    skipTurbo?: boolean
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    __prefetched_data?: any
  }
}

export function currentState(): HistoryState {
  return ssrSafeHistory?.state || {}
}

export function updateUrl(newUrl: string) {
  replaceStateWithEvent(currentState(), '', newUrl)
}

export function addUrlToHistoryStack(newUrl: string) {
  ssrSafeHistory?.pushState({appId: currentState().appId}, '', newUrl)
  dispatchStateChange()
}

export function updateCurrentState(state: HistoryState) {
  const mergedState = {
    ...currentState(),
    ...state,
  }
  replaceStateWithEvent(mergedState, '', location.href)
}

export function updateSearchParams(searchParams: URLSearchParams) {
  updateUrl(`?${searchParams.toString()}${ssrSafeLocation.hash}`)
}

export function removeSearchParams() {
  updateUrl(ssrSafeLocation.pathname + ssrSafeLocation.hash)
}

export function updateUrlHash(hash: string) {
  const hashWithPrefix = hash.startsWith('#') ? hash : `#${hash}`
  updateUrl(hashWithPrefix)
}

export function removeUrlHash() {
  updateUrl(ssrSafeLocation.pathname + ssrSafeLocation.search)
}

export function goBack() {
  ssrSafeHistory?.back()
}

export function goForward() {
  ssrSafeHistory?.forward()
}

function replaceStateWithEvent(data: HistoryState, unused: string, url: string | URL) {
  ssrSafeHistory?.replaceState(data, unused, url)
  dispatchStateChange()
}

function dispatchStateChange() {
  ssrSafeWindow?.dispatchEvent(new CustomEvent('statechange', {bubbles: false, cancelable: false}))
}
