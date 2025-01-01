import {useSyncExternalStore} from 'react'

// Safari has issues with position sticky, so expose a hook to check if we are in Safari
export function useIsSafari() {
  return useSyncExternalStore(subscribe, isSafariInBrowser, isSafariOnServer)
}
function isSafariInBrowser() {
  return /^((?!chrome|android).)*safari/i.test(navigator.userAgent)
}

function isSafariOnServer() {
  return false
}

//this is just a no-op, it has to be verbose because otherwise the linter is not happy
function subscribe() {
  return () => {
    return
  }
}
