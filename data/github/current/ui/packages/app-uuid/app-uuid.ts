import {currentState, updateCurrentState} from '@github-ui/history'
import {ssrSafeWindow} from '@github-ui/ssr-utils'

// Use this mock interface to avoid importing ReactAppElement or ProjectsV2 here.
interface AppWithUuid extends Element {
  uuid: string
}

export const generateAppId = () => {
  const historyAppId = currentState().appId
  // When first loading an app, generate a new uuid to identify it
  if (!historyAppId || historyAppId === 'rails') {
    return crypto.randomUUID()
  }

  // If the app is being restored from History, keep its uuid
  return historyAppId
}

export const registerAppId = (uuid: string) => {
  updateCurrentState({appId: uuid})
}

export const currentAppId = () => {
  const currentApp =
    document.querySelector<AppWithUuid>('react-app') || document.querySelector<AppWithUuid>('projects-v2')

  return currentApp?.uuid || 'rails'
}

// when the hash changes, we want to propagate the appId from the current state
ssrSafeWindow?.addEventListener(
  'hashchange',
  () => {
    updateCurrentState({appId: currentAppId()})
  },
  true,
)
