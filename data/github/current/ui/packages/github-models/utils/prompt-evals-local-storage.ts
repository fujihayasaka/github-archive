import safeStorage from '@github-ui/safe-storage'
import type {EvalsState, MessagePair, PlaygroundRequestParameters} from '../types'

export const PROMPT_EVALS_LOCAL_STORAGE_KEY = 'models-prompt-evals'
const ONE_DAY_IN_MS = 1000 * 60 * 60 * 24

export type PromptEvalsLocalStorage = {
  prompt: string
  evals: EvalsState
  systemPrompt?: string
  parameters?: PlaygroundRequestParameters
  messagePairs?: MessagePair[]
}

const safeLocalStorage = safeStorage('localStorage', {
  ttl: ONE_DAY_IN_MS,
  throwQuotaErrorsOnSet: false,
})

export function getPromptEvalsLocalStorage() {
  const savedState = safeLocalStorage.getItem(PROMPT_EVALS_LOCAL_STORAGE_KEY)
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

export function setPromptEvalsLocalStorage(state: PromptEvalsLocalStorage) {
  const value = JSON.stringify(state)
  safeLocalStorage.setItem(PROMPT_EVALS_LOCAL_STORAGE_KEY, value)
}
