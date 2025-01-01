import {getItem, setItem} from '@github-ui/safe-storage/session-storage'
import {DEFAULT_HEIGHT, DEFAULT_WIDTH} from './constants'
import {ReactQueryDevtoolResizeEvent, ReactQueryDevtoolToggleEvent} from './events'

const REACT_QUERY_DEVTOOLS_SESSION_STORAGE_KEY_BASE = 'github_session_staffbar_react_query_devtools'
function getSessionKey(value: string) {
  return `${REACT_QUERY_DEVTOOLS_SESSION_STORAGE_KEY_BASE}.${value}`
}
const IS_OPEN_KEY = getSessionKey('isOpen')
const WIDTH_KEY = getSessionKey('panelWidth')
const HEIGHT_KEY = getSessionKey('panelHeight')

function getNumberFromSessionStore(key: string, defaultValue: number): number {
  if (typeof window !== 'undefined') {
    const item = getItem(key)
    if (item) {
      const value = parseFloat(item)
      if (!Number.isNaN(value)) return value
    }
  }
  return defaultValue
}

function createSizeSetter(key: string, defaultValue: number) {
  return function set(next: number | ((v: number) => number)) {
    if (typeof next !== 'function') {
      setItem(key, JSON.stringify(next))
    } else {
      const current = getNumberFromSessionStore(key, defaultValue)
      setItem(key, JSON.stringify(next(current)))
    }
    document.dispatchEvent(new ReactQueryDevtoolResizeEvent())
  }
}

export const setSessionWidth = createSizeSetter(WIDTH_KEY, DEFAULT_WIDTH)
export const setSessionHeight = createSizeSetter(HEIGHT_KEY, DEFAULT_HEIGHT)
export function getSessionHeight() {
  return getNumberFromSessionStore(HEIGHT_KEY, DEFAULT_WIDTH)
}
export function getSessionWidth() {
  return getNumberFromSessionStore(WIDTH_KEY, DEFAULT_WIDTH)
}

export function getIsQueryPanelOpen(): boolean {
  return getItem(IS_OPEN_KEY) === 'true'
}

export function setIsQueryPanelOpen(next: boolean) {
  setItem(IS_OPEN_KEY, JSON.stringify(next))
  document.dispatchEvent(new ReactQueryDevtoolToggleEvent())
}
