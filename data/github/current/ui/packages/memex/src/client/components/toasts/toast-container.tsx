import {createContext, memo, useMemo} from 'react'

import Toast from './toast'
import type {AddToastProps, ToastItem} from './types'
import useToastsInternal from './use-toasts-internal'

export interface ToastContextInterface {
  /** Display a transient toast message to the viewer */
  addToast: (args: AddToastProps) => number
  /** Explicitly dismiss a transient toast, instead of waiting for autodismiss or the user to press "X". */
  removeToast: (id: number) => void
  /** Display a toast message to the viewer that will persist until it is explicitly dismissed. */
  addPersistedToast: (content: AddToastProps) => void
  /** Update the content of the persisted tost */
  updatePersistedToast: (content: AddToastProps) => void
  /** Remove the persisted toast */
  clearPersistedToast: () => void
}
export const ToastContext = createContext<ToastContextInterface | null>(null)

interface ToastContainerProps {
  /**
   * Global setting for whether the toasts will clear after a given period
   * of time. Defaults to true if omitted.
   */
  autoDismiss?: boolean
  /**
   * Specify the default timeout before toasts are removed
   */
  timeout?: number
}

/**
 * Context Provider for {@see ToastContext} exposes API for adding toast.
 *
 * This handles rendering the inner {@see Toast} components alongside the
 * related child components.
 */
const ToastContainer = memo<React.PropsWithChildren<ToastContainerProps>>(function ToastContainer(props) {
  const {autoDismiss, timeout, children} = props
  const {
    addToast,
    removeToast,
    toasts,
    persistedToast,
    addPersistedToast,
    updatePersistedToast,
    clearPersistedToast,
    ...toastProps
  } = useToastsInternal({
    autoDismiss,
    timeout,
  })
  const value = useMemo(
    () => ({addToast, removeToast, addPersistedToast, updatePersistedToast, clearPersistedToast}),
    [addToast, removeToast, addPersistedToast, updatePersistedToast, clearPersistedToast],
  )

  return (
    <ToastContext.Provider value={value}>
      {children}
      {toasts &&
        toasts.map((toast: ToastItem) => {
          return <Toast key={toast.id} toast={toast} removeToast={removeToast} {...toastProps} />
        })}
      {persistedToast && (
        <Toast key={persistedToast.id} toast={persistedToast} startRemovingToast={clearPersistedToast} />
      )}
    </ToastContext.Provider>
  )
})

export default ToastContainer
