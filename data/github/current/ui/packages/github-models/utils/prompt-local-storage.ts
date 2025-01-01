import safeStorage from '@github-ui/safe-storage'
import type {MessagePair, PlaygroundRequestParameters} from '../types'

export const PROMPT_LOCAL_STORAGE_KEY = 'models-prompt-'
const ONE_DAY_IN_MS = 1000 * 60 * 60 * 24

export type PromptLocalStorage = {
  prompt: string
  systemPrompt?: string
  parameters?: PlaygroundRequestParameters
  messagePairs?: MessagePair[]
}

const safeLocalStorage = safeStorage('localStorage', {
  ttl: ONE_DAY_IN_MS,
  throwQuotaErrorsOnSet: false,
})

export function getPromptLocalStorage() {
  const savedState = safeLocalStorage.getItem(PROMPT_LOCAL_STORAGE_KEY)
  return savedState
    ? JSON.parse(savedState, (key, value) => {
        if (key === 'timestamp') {
          return new Date(value)
        } else {
          return value
        }
      })
    : null
}

export function setPromptLocalStorage(state: PromptLocalStorage) {
  const value = JSON.stringify(state)
  safeLocalStorage.setItem(PROMPT_LOCAL_STORAGE_KEY, value)
}
