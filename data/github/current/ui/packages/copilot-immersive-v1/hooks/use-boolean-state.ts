import {useCallback, useState} from 'react'

/**
 * Easy boolean state manager. Returns two stable state setters instead of one, allowing you to combine a `useState`
 * and two `useCallback` calls into one single `useBooleanState` call.
 */
export function useBooleanState(initialValue: boolean): [value: boolean, setTrue: () => void, setFalse: () => void] {
  const [state, setState] = useState(initialValue)
  const setTrue = useCallback(() => setState(true), [])
  const setFalse = useCallback(() => setState(false), [])
  return [state, setTrue, setFalse] as const
}
