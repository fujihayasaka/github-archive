import {useCallback, useEffect, useRef, useState, type RefObject} from 'react'

function containsRelatedTarget(event: FocusEvent) {
  if (event.currentTarget instanceof HTMLElement && event.relatedTarget instanceof HTMLElement) {
    return event.currentTarget.contains(event.relatedTarget)
  }

  return false
}

export function useFocusWithin<T extends HTMLElement>({
  onBlur,
  onFocus,
}: {
  onFocus?: (event: FocusEvent) => void
  onBlur?: (event: FocusEvent) => void
}): {
  ref: RefObject<T>
  isFocused: boolean
} {
  const [isFocused, setIsFocused] = useState(false)
  const ref = useRef<T>(null)

  const handleFocusIn = useCallback(
    (event: FocusEvent) => {
      setIsFocused(true)
      onFocus?.(event)
    },
    [onFocus],
  )

  const handleFocusOut = useCallback(
    (event: FocusEvent) => {
      if (!containsRelatedTarget(event)) {
        setIsFocused(false)
        onBlur?.(event)
      }
    },
    [onBlur],
  )

  useEffect(() => {
    const element = ref.current
    if (!element) return

    element.addEventListener('focusin', handleFocusIn)
    element.addEventListener('focusout', handleFocusOut)

    return () => {
      element.removeEventListener('focusin', handleFocusIn)
      element.removeEventListener('focusout', handleFocusOut)
    }
  }, [handleFocusIn, handleFocusOut])

  return {ref, isFocused}
}
