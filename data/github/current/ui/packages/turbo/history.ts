import {navigator, session} from '@github/turbo'
import {currentState} from '@github-ui/history'
import {currentAppId} from '@github-ui/app-uuid'

type State = Record<string, unknown> & {
  turbo?: {restorationIdentifier: string}
  turboCount?: number
  appId?: string
}

// Turbo should restore the page on b/f navigation whenever we cross app boundaries or are going from rails to rails.
session.history.shouldRestore = (state?: State) => {
  const currentApp = currentAppId()
  const stateAppId = state?.appId
  return currentApp !== stateAppId || (stateAppId === 'rails' && currentApp === 'rails') || !stateAppId
}

// keep Turbo's history up to date with the browser's in case code calls native history API's directly
const patchHistoryApi = (name: 'replaceState' | 'pushState') => {
  // eslint-disable-next-line no-restricted-globals
  const oldHistory = history[name]

  // eslint-disable-next-line no-restricted-globals
  history[name] = function (this: History, state?: State, unused?: string, url?: string | URL | null) {
    // we need to merge the state from turbo with the state given to pushState in case others are adding data to the state
    function oldHistoryWithMergedState(
      this: History,
      turboState: State,
      turboUnused: string,
      turboUrl?: string | URL | null,
    ) {
      const currentTurboCount = currentState().turboCount || 0
      const isTurboNav = name === 'pushState' && state?.turbo

      // The only places that actively sets the appId are:
      //  1. during ReactAppElement connectedCallback.
      //  2. when turbo is pushing a state (turbo navs)
      // We want to make sure the app registers itself in the history state and propagate it between
      // soft navs and other state changes.
      const appId = isTurboNav ? 'rails' : state?.appId || currentState().appId

      // Only turbo navs have the `turbo` key when pushing state.
      const turboCount = isTurboNav ? currentTurboCount + 1 : currentTurboCount

      const mergedState = {...state, ...turboState, turboCount, appId}
      oldHistory.call(this, mergedState, turboUnused, turboUrl)
    }

    navigator.history.update(
      oldHistoryWithMergedState,
      new URL(url || location.href, location.href),
      state?.turbo?.restorationIdentifier,
    )
  }
}

patchHistoryApi('replaceState')
patchHistoryApi('pushState')
