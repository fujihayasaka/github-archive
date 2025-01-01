import safeStorage from '@github-ui/safe-storage'

const sessionStorage = safeStorage('sessionStorage', {
  throwQuotaErrorsOnSet: false,
  ttl: 1000 * 60 * 60 * 24,
})

interface ThreadTimePatch {
  threadID: string
  updatedAt: number
}

const THREAD_TIME_PATCH_KEY = 'THREAD_TIME_PATCH'

export function getThreadTimePatch(): ThreadTimePatch | null {
  const threadTimePatch = sessionStorage.getItem(THREAD_TIME_PATCH_KEY)
  return threadTimePatch ? (JSON.parse(threadTimePatch) as ThreadTimePatch) : null
}

export function setThreadTimePatch(threadID: string, time: number) {
  const threadTimePatch: ThreadTimePatch = {threadID, updatedAt: time}
  sessionStorage.setItem(THREAD_TIME_PATCH_KEY, JSON.stringify(threadTimePatch))
}

export function clearThreadTimePatch() {
  sessionStorage.removeItem(THREAD_TIME_PATCH_KEY)
}
