import safeStorage from '@github-ui/safe-storage'
import {type Dispatch, useCallback, useEffect, useMemo, useRef, useState} from 'react'

const safeLocalStorage = safeStorage('localStorage')

const USE_LOCAL_STORAGE_UPDATE_EVENT_NAME = 'local-storage-gc-update'

const defaultTtl = 30 * 24 * 60 * 60 // 30 days

class UseLocalStorageUpdateEvent extends Event {
  declare storageKey: string
  declare storageValue: unknown | undefined

  constructor(storageKey: string, storageValue: unknown | undefined) {
    super(USE_LOCAL_STORAGE_UPDATE_EVENT_NAME)
    this.storageKey = storageKey
    this.storageValue = storageValue
  }
}

declare global {
  interface DocumentEventMap {
    [USE_LOCAL_STORAGE_UPDATE_EVENT_NAME]: UseLocalStorageUpdateEvent
  }
}

interface ExpiringItem<T> {
  value: T
  deleteAfter?: number
}

const PREFIX = 'exp:'
/**
 * Fork of useLocalStorage that adds deleteAfter to the stored value so
 * "expired" values can be cleaned up.
 *
 * @see {@link useLocalStorage}
 *
 * @param storageKey - The key to use in local storage
 * @param fallbackState - The initial value to use if the key is not in local storage
 * @param ttlSeconds - (optional, 30d default) The time in seconds from when the value is set that it should be deleted
 * @returns [T, (value: T) => void] Reader and setter functions
 */
export function useLocalStorageWithExpiry<T>(
  storageKey: string,
  fallbackState: T,
  ttlSeconds?: number,
): readonly [T, (value: T) => void] {
  // Set the TTL to 30 days if not provided
  const ttlMillis = (ttlSeconds ?? defaultTtl) * 1000
  // Prefix the provided storage key with a known value
  storageKey = PREFIX + storageKey
  // Clean out any stale values
  // eslint-disable-next-line react-compiler/react-compiler
  useMemo(flushLocalStorage, [])

  const wrapValue = useCallback(
    (value: T) => {
      return {value, deleteAfter: Date.now() + ttlMillis}
    },
    [ttlMillis],
  )

  // copy fallbackState to a tracked ref, to avoid re-renders if it has unstable identity
  const fallBackWithExp = wrapValue(fallbackState)
  const fallbackStateRef = useRef<ExpiringItem<T>>(fallBackWithExp)
  useEffect(() => {
    fallbackStateRef.current = fallBackWithExp
  })

  const [value, setValue] = useState<ExpiringItem<T>>(() => {
    const itemValue = safeLocalStorage.getItem(storageKey)
    if (itemValue) {
      // Update TTL
      return JSON.parse(itemValue)
    }
    return fallbackStateRef.current
  })

  const setNextValue: Dispatch<T> = useCallback(
    (nextValue: undefined | T) => {
      if (nextValue === undefined) {
        setValue(fallbackStateRef.current)
        safeLocalStorage.removeItem(storageKey)
      } else {
        const valueWithExp = wrapValue(nextValue)
        setValue(valueWithExp)
        safeLocalStorage.setItem(storageKey, JSON.stringify(valueWithExp))
      }

      document.dispatchEvent(new UseLocalStorageUpdateEvent(storageKey, nextValue))
    },
    [storageKey, wrapValue],
  )

  /**
   * When we change the value, we emit an event
   *
   * Subscribe to that event, so we can continuously sync
   * the state
   */
  useEffect(() => {
    function handler(event: UseLocalStorageUpdateEvent) {
      if (event.storageKey === storageKey) {
        const nextValue: T = (event.storageValue as T | undefined) ?? fallbackStateRef.current.value
        setValue(wrapValue(nextValue))
      }
    }

    document.addEventListener(USE_LOCAL_STORAGE_UPDATE_EVENT_NAME, handler)

    /**
     * during setup, it's _possible_ we've diverged, so we'll
     * immediately check for an update
     *
     * This also provides a 'reset' in the event the storageKey was changed
     */
    const itemValue = safeLocalStorage.getItem(storageKey)
    if (itemValue) {
      setValue(JSON.parse(itemValue))
    } else {
      setValue(fallbackStateRef.current)
    }

    return () => {
      document.removeEventListener(USE_LOCAL_STORAGE_UPDATE_EVENT_NAME, handler)
    }
  }, [storageKey, wrapValue])

  return [value.value, setNextValue] as const
}

/**
 * Flushes any expired values from local storage
 */
function flushLocalStorage() {
  for (const key in localStorage) {
    if (key.startsWith(PREFIX)) {
      const value = JSON.parse(localStorage.getItem(key) || '{}')
      if (value.deleteAfter && value.deleteAfter < Date.now()) {
        localStorage.removeItem(key)
      }
    }
  }
}
