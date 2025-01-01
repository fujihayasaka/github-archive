import {useCallback, useRef, useState} from 'react'

import {useTimeout} from '../../hooks/common/timeouts/use-timeout'
import {
  type AddToastProps,
  DEFAULT_TOAST_TIMEOUT,
  PERSISTED_TOAST_ID,
  TOAST_ANIMATION_LENGTH,
  type ToastItem,
} from './types'

/**
 * Internal API for managing toasts within the application.
 *
 * This handles the lifecycle of toasts and cleaning up the toasts as they
 * expire.
 *
 * By default this will auto-dismiss toasts after 15 seconds.
 */
const useToastsInternal = ({autoDismiss = true, timeout = DEFAULT_TOAST_TIMEOUT} = {}) => {
  const [toasts, setToasts] = useState<Array<ToastItem>>([])
  const [persistedToast, setPersistedToast] = useState<ToastItem | null>(null)
  const nextId = useRef(0)
  const getNextId = () => nextId.current++

  const findToastById = useCallback((id: number) => toasts.find(toast => toast.id === id), [toasts])

  const setToastsAfterAnimationDuration = useTimeout(setToasts, TOAST_ANIMATION_LENGTH)

  const removeToast = useCallback(
    (id: number) => {
      const currentToast = findToastById(id)

      if (!currentToast) return

      currentToast.timeout?.cancel()

      setToasts(currentToasts => currentToasts.filter(toast => toast.id !== currentToast.id))

      if (currentToast.onDismiss) {
        currentToast.onDismiss()
      }
    },
    [findToastById, setToasts],
  )
  const removeToastAfterAnimationDuration = useTimeout(removeToast, TOAST_ANIMATION_LENGTH)

  // find the toast to remove and add the `toast-leave` class name
  const startRemovingToast = useCallback(
    (id: number) => {
      setToasts(prevState => prevState.map(toast => (toast.id === id ? {...toast, className: 'toast-leave'} : toast)))
      removeToastAfterAnimationDuration(id)
    },
    [removeToastAfterAnimationDuration, setToasts],
  )
  const dismissToastAfterTimeout = useTimeout(startRemovingToast, timeout)

  const removePersistedToastAfterAnimationDuration = useTimeout(() => setPersistedToast(null), TOAST_ANIMATION_LENGTH)
  const startRemovingPersistedToast = useCallback(() => {
    setPersistedToast(prevState => prevState && {...prevState, className: 'toast-leave'})
    removePersistedToastAfterAnimationDuration()
  }, [removePersistedToastAfterAnimationDuration, setPersistedToast])

  const addPersistedToast = useCallback(
    (content: AddToastProps) => {
      if (persistedToast) return

      const newToast = {id: PERSISTED_TOAST_ID, ...content}

      const activeToast = toasts[0]
      if (activeToast) {
        startRemovingToast(activeToast.id)
        setToastsAfterAnimationDuration([])
      }

      setPersistedToast(newToast)
    },
    [persistedToast, toasts, startRemovingToast, setToastsAfterAnimationDuration, setPersistedToast],
  )

  const updatePersistedToast = useCallback(
    (content: AddToastProps) => {
      if (!persistedToast) return
      setPersistedToast({id: PERSISTED_TOAST_ID, ...content})
    },
    [persistedToast, setPersistedToast],
  )

  const clearPersistedToast = useCallback(() => {
    if (!persistedToast) return
    startRemovingPersistedToast()
  }, [persistedToast, startRemovingPersistedToast])

  const addToast = useCallback(
    (freshToast: AddToastProps) => {
      clearPersistedToast()

      const toastId = getNextId()

      let timeoutInstance
      if (autoDismiss && !freshToast.keepAlive) {
        timeoutInstance = dismissToastAfterTimeout(toastId)
      }
      const newToast = {id: toastId, timeout: timeoutInstance, ...freshToast}
      // if there's already a toast on the page, wait for it to animate out before
      // adding a new toast
      const firstToast = toasts[0]
      if (firstToast) {
        startRemovingToast(firstToast.id)
        setToastsAfterAnimationDuration([newToast])
      } else {
        setToasts([newToast])
      }
      return toastId
    },
    [
      autoDismiss,
      dismissToastAfterTimeout,
      setToastsAfterAnimationDuration,
      startRemovingToast,
      toasts,
      clearPersistedToast,
    ],
  )

  return {
    addToast,
    toasts,
    removeToast,
    startRemovingToast,
    addPersistedToast,
    updatePersistedToast,
    clearPersistedToast,
    persistedToast,
  }
}

export default useToastsInternal
