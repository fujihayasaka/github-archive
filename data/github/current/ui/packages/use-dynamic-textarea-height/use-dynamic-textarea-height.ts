import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {type RefObject, useCallback, useEffect, useMemo, useState} from 'react'

type UseDynamicTextareaHeightSettings = {
  disabled?: boolean
  minHeightLines?: number
  maxHeightLines?: number
  elementRef: RefObject<HTMLTextAreaElement | null>
  /** The current value of the input. */
  value: string
}

/**
 * Calculates the optimal height of the textarea according to its content, automatically
 * resizing it as the user types. If the user manually resizes the textarea, their setting
 * will be respected.
 *
 * Returns an object to spread to the component's `style` prop. If you are using `Textarea`,
 * apply this to the child `textarea` element: `<Textarea style={{resultOfThisHook}} />`.
 *
 * NOTE: for the most accurate results, be sure that the `lineHeight` of the element is
 * explicitly set in CSS.
 */
export const useDynamicTextareaHeight = ({
  disabled,
  minHeightLines,
  maxHeightLines,
  elementRef,
  value,
}: UseDynamicTextareaHeightSettings): {
  height: string | undefined
  minHeight: string | undefined
  maxHeight: string | undefined
  boxSizing: 'content-box'
  fieldSizing: 'content'
} => {
  const [height, setHeight] = useState<string | undefined>(undefined)
  const supportsFieldSizingContent = useMemo(() => CSS?.supports?.('field-sizing', 'content'), [])

  const refreshHeight = useCallback(() => {
    if (disabled) return

    const element = elementRef.current
    if (!element) return

    // If the browser supports `field-sizing: content`, we can use that to avoid calculating the height ourselves.
    // This is a CSS property that allows the browser to automatically size the field based on its content.
    if (supportsFieldSizingContent) return

    // If the value is empty, we don't need to calculate a dynamic height
    if (!value) return

    const computedStyles = getComputedStyle(element)
    // Using CSS calculations is fast and prevents us from having to parse anything
    setHeight(`calc(${element.scrollHeight}px - ${computedStyles.paddingTop} - ${computedStyles.paddingBottom})`)
  }, [disabled, elementRef, supportsFieldSizingContent, value])

  useLayoutEffect(refreshHeight, [refreshHeight])

  // With Slots, initial render of the component is delayed and so the initial layout effect can occur
  // before the target element has actually been calculated in the DOM. But if we only use regular effects,
  // there will be a visible flash on initial render when not using slots
  // eslint-disable-next-line react-hooks/react-compiler
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(refreshHeight, [])

  return {
    height,
    minHeight: minHeightLines ? `${minHeightLines}lh` : undefined,
    maxHeight: maxHeightLines ? `${maxHeightLines}lh` : undefined,
    boxSizing: 'content-box',
    fieldSizing: 'content',
  }
}
