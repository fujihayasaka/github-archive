import safeStorage from '@github-ui/safe-storage'
import {SidebarSelectionOptions, type GettingStarted, type PlaygroundMessage, type TokenUsage} from '../types'

const ONE_DAY_IN_MS = 1000 * 60 * 60 * 24
export const UI_STATE_KEY = 'models:uiState'

export type StoredChatMessages = {
  modelName: string
  messages: PlaygroundMessage[]
  tokenUsage?: TokenUsage
}

const safeLocalStorage = safeStorage('localStorage', {
  ttl: ONE_DAY_IN_MS,
  throwQuotaErrorsOnSet: false,
})

export function getSavedPlaygroundMessages() {
  const savedMessages = safeLocalStorage.getItem('playground-chat-messages')
  return savedMessages
    ? JSON.parse(savedMessages, (key, value) => {
        if (key === 'timestamp') {
          return new Date(value)
        } else {
          return value
        }
      })
    : null
}

export function setPlaygroundLocalStorageMessages(chatMessages: StoredChatMessages) {
  const value = JSON.stringify(chatMessages)
  safeLocalStorage.setItem('playground-chat-messages', value)
}

export function clearPlaygroundLocalStorage() {
  safeLocalStorage.removeItem('playground-chat-messages')
}

export type SidebarSelection = 'parameters' | 'details'

export type ModelPersistentUIState = {
  sidebarTab: SidebarSelectionOptions
  showSidebar: boolean
  preferredLanguage: string // value is validated by the components, as it depends on the model
  preferredSdk: string // value is validated by the components, as it depends on the model
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function isValidModelPersistentUIState(state: any): state is ModelPersistentUIState {
  const validKeys: Array<keyof ModelPersistentUIState> = [
    'sidebarTab',
    'showSidebar',
    'preferredLanguage',
    'preferredSdk',
  ]

  return (
    typeof state === 'object' &&
    state !== null &&
    validKeys.every(key => key in state) &&
    typeof state.sidebarTab === 'number' &&
    typeof state.showSidebar === 'boolean' &&
    typeof state.preferredLanguage === typeof 'string' &&
    typeof state.preferredSdk === typeof 'string'
  )
}

export const defaultUiState: ModelPersistentUIState = {
  sidebarTab: SidebarSelectionOptions.PARAMETERS,
  showSidebar: true,
  preferredLanguage: 'js',
  preferredSdk: '',
}

export const getLocalStorageUiState = () => {
  try {
    const storedStateJSON = safeLocalStorage.getItem(UI_STATE_KEY)
    if (storedStateJSON) {
      const storedState = JSON.parse(storedStateJSON)
      if (storedState) {
        return isValidModelPersistentUIState(storedState) ? storedState : defaultUiState
      }
    }
  } catch {
    return defaultUiState
  }
  return defaultUiState
}

export const setLocalStorageUiState = (uiState: ModelPersistentUIState) => {
  safeLocalStorage.setItem(UI_STATE_KEY, JSON.stringify(uiState))
}

export const getDefaultUiState = (
  gettingStarted?: GettingStarted,
  preferredLanguage?: string,
  preferredSdk?: string,
): ModelPersistentUIState => {
  const localStorageUiState = getLocalStorageUiState()

  if (!gettingStarted) {
    return localStorageUiState
  }

  // Check if the preferred language is valid
  const language = preferredLanguage || localStorageUiState.preferredLanguage
  const validLanguage = gettingStarted[language] ? language : Object.keys(gettingStarted)[0] || null

  // Check if the preferred sdk is valid
  const sdk = preferredSdk || localStorageUiState.preferredSdk
  let validSdk = null
  if (validLanguage) {
    const languageEntry = gettingStarted[validLanguage]
    if (languageEntry) {
      const sdks = Object.keys(languageEntry.sdks)
      if (sdks.includes(sdk)) {
        validSdk = sdk
      } else {
        validSdk = sdks[0] || null
      }
    }
  }
  return {
    ...localStorageUiState,
    ...(validLanguage && {preferredLanguage: validLanguage}),
    ...(validSdk && {preferredSdk: validSdk}),
  }
}
