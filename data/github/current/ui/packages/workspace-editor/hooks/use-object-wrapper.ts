import {type MutableRefObject, useRef} from 'react'

/**
 * Simple hook that wraps the provided value in a ref, returns the ref, and updates the ref's value whenever the
 * provided value changes.
 */
export function useObjectWrapper<T>(value: T): MutableRefObject<T> {
  const ref = useRef<T>(value)
  ref.current = value
  return ref
}
