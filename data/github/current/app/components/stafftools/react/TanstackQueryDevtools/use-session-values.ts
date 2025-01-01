import {useSyncExternalStore} from 'react'
import {DEFAULT_EDGE_BUFFER, DEFAULT_HEIGHT, DEFAULT_WIDTH, minHeight, minWidth} from './constants'
import {subscribeToBodyResize, subscribeToSessionResize} from './events'
import {getSessionHeight, getSessionWidth} from './session-store'

function getClientMaxHeight() {
  return window.innerHeight - DEFAULT_EDGE_BUFFER
}
function getClientMaxWidth() {
  return window.innerWidth - DEFAULT_EDGE_BUFFER
}
function getDefaultHeight() {
  return DEFAULT_HEIGHT
}
function getDefaultWidth() {
  return DEFAULT_WIDTH
}

const usePanelHeight = () => useSyncExternalStore(subscribeToSessionResize, getSessionHeight, getDefaultHeight)
const usePanelWidth = () => useSyncExternalStore(subscribeToSessionResize, getSessionWidth, getDefaultWidth)
const usePanelMaxHeight = () => useSyncExternalStore(subscribeToBodyResize, getClientMaxHeight, getDefaultHeight)
const usePanelMaxWidth = () => useSyncExternalStore(subscribeToBodyResize, getClientMaxWidth, getDefaultWidth)

export const useSessionSizes = () => {
  const height = usePanelHeight()
  const width = usePanelWidth()
  const maxWidth = usePanelMaxWidth()
  const maxHeight = usePanelMaxHeight()

  const constrainedWidth = Math.max(minWidth, Math.min(width, maxWidth))
  const constrainedHeight = Math.max(minHeight, Math.min(height, maxHeight))
  return {
    height: constrainedHeight,
    width: constrainedWidth,
    maxWidth,
    maxHeight,
    minHeight,
    minWidth,
  }
}
