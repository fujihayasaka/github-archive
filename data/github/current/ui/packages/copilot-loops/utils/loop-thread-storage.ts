import safeStorage from '@github-ui/safe-storage'
import {logWarning} from './console'

const localStorage = safeStorage('localStorage')

const LOOP_THREAD_ID_PREFIX = 'copilot-loops-thread-'

/**
 * Get the thread ID associated with a loop from local storage
 * @param loopId - The ID of the loop
 * @returns The thread ID or null if not found
 */
export function getLoopThreadId(loopId: string): string | null {
  try {
    const key = `${LOOP_THREAD_ID_PREFIX}${loopId}`
    return localStorage.getItem(key)
  } catch (error) {
    logWarning('Failed to read loop thread ID from localStorage:', error)
    return null
  }
}

/**
 * Store the thread ID associated with a loop in local storage
 * @param loopId - The ID of the loop
 * @param threadId - The thread ID to store
 */
export function setLoopThreadId(loopId: string, threadId: string | null): void {
  if (threadId === null) return

  try {
    const key = `${LOOP_THREAD_ID_PREFIX}${loopId}`
    localStorage.setItem(key, threadId)
  } catch (error) {
    logWarning('Failed to store loop thread ID in localStorage:', error)
  }
}

/**
 * Remove the thread ID associated with a loop from local storage
 * @param loopId - The ID of the loop
 */
export function removeLoopThreadId(loopId: string): void {
  try {
    const key = `${LOOP_THREAD_ID_PREFIX}${loopId}`
    localStorage.removeItem(key)
  } catch (error) {
    logWarning('Failed to remove loop thread ID from localStorage:', error)
  }
}
