import safeStorage from '@github-ui/safe-storage'

const WORKBENCH_COPILOT_THREAD_MAP = 'workbench-copilot-thread-map'
const WORKBENCH_CHAT_QUOTA_APPROACHING = 'workbench-chat-quota-approaching'
const WORKBENCH_PROMPT_SUBMIT_TIMESTAMP = 'workbench-submit-timestamp'
export const WORKBENCH_PROMPT_SUBMIT_TIMESTAMP_UPDATED = 'copilotSubmitTimestampUpdated'

function getSafeLocalStorage() {
  return safeStorage('localStorage', {
    throwQuotaErrorsOnSet: false,
    ttl: 1000 * 60 * 60 * 24,
  })
}

function getThreadMap(): Record<string, string> {
  const threadMap = getSafeLocalStorage().getItem(WORKBENCH_COPILOT_THREAD_MAP)
  if (threadMap) {
    return JSON.parse(threadMap)
  }
  return {}
}

function setThreadMap(threadMap: Record<string, string>) {
  getSafeLocalStorage().setItem(WORKBENCH_COPILOT_THREAD_MAP, JSON.stringify(threadMap))
}

/**
 * Save the Copilot chat thread id for the given PR in local storage
 */
export function getSelectedThreadID(sparkId: string): string | null {
  const threadMap = getThreadMap()
  const threadID = threadMap[sparkId]
  return threadID || null
}

/**
 * Get the Copilot chat thread id for the given PR from local storage
 */
export function setSelectedThreadID(sparkId: string, threadID: string | null) {
  const threadMap = getThreadMap()
  if (threadID) {
    threadMap[sparkId] = threadID
  } else {
    delete threadMap[sparkId]
  }
  setThreadMap(threadMap)
}

/**
 * Get the Copilot chat quota approaching flag from local storage
 */
export function getChatQuotaApproaching(): boolean | null {
  const value = getSafeLocalStorage().getItem(WORKBENCH_CHAT_QUOTA_APPROACHING)
  return value === null ? null : value === 'true'
}

/**
 * Set the Copilot chat quota approaching flag in local storage
 */
export function setChatQuotaApproaching(value: boolean = false) {
  getSafeLocalStorage().setItem(WORKBENCH_CHAT_QUOTA_APPROACHING, value.toString())
}

/**
 * Remove the Copilot chat quota approaching flag from local storage
 */
export function removeChatQuotaApproaching() {
  getSafeLocalStorage().removeItem(WORKBENCH_CHAT_QUOTA_APPROACHING)
}

/**
 * Set submit timestamp in local storage
 */
export function setSubmitTimestamp() {
  const timestamp = Date.now().toString()
  getSafeLocalStorage().setItem(WORKBENCH_PROMPT_SUBMIT_TIMESTAMP, timestamp)
  window.dispatchEvent(new Event(WORKBENCH_PROMPT_SUBMIT_TIMESTAMP_UPDATED))
}

/**
 * Get submit timestamp from local storage
 * @returns {number | null} The submit timestamp or null if not set
 */
export function getSubmitTimestamp(): number | null {
  const timestamp = getSafeLocalStorage().getItem(WORKBENCH_PROMPT_SUBMIT_TIMESTAMP)
  return timestamp ? parseInt(timestamp, 10) : null
}

export function workspaceEditorIntegrationId(): string {
  return process.env.NODE_ENV === 'development' ? 'copilot_workspace_hadron_dev' : 'copilot_workspace_hadron'
}
