import safeStorage from '@github-ui/safe-storage'

const WORKBENCH_COPILOT_THREAD_MAP = 'workbench-copilot-thread-map'

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

export function workspaceEditorIntegrationId(): string {
  return process.env.NODE_ENV === 'development' ? 'copilot_workspace_hadron_dev' : 'copilot_workspace_hadron'
}
