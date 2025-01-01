import {useSyncExternalStore} from 'react'
import {subscribeToToggleEvent} from './events'
import {getIsQueryPanelOpen} from './session-store'

function getServerIsPanelOpen() {
  return false
}

export function useDevToolsOpenState() {
  return useSyncExternalStore(subscribeToToggleEvent, getIsQueryPanelOpen, getServerIsPanelOpen)
}
