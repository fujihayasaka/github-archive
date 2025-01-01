// Most code was extracted and adapted from the classic experience implemented in
// app/assets/modules/github/issues/convert-to-issue-button.ts

import {useState} from 'react'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type {SafeHTMLString} from '@github-ui/safe-html'
/**
 * Checks if two arrays are equal.
 * @param a - The first array.
 * @param b - The second array.
 * @returns True if the arrays are equal, false otherwise.
 */
function arraysEqual(a: unknown[], b: unknown[]) {
  if (a.length !== b.length) return false

  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false

  return true
}

const defaultArray: HTMLElement[] = []
/**
 * Returns an array of elements that match the specified selector within a container.
 *
 * @param containerRef - A React ref object that references the container element.
 * @param selector - A CSS selector string used to select elements within the container.
 * @returns An array of elements that match the selector.
 */
export function useQuerySelectorAll(
  containerRef: React.RefObject<Element>,
  selector: string,
  verifiedHTML: SafeHTMLString,
) {
  const [elements, setElements] = useState<Element[]>([])

  // We do want this to run on every render. It will only trigger a rerender if the elements have changed
  useLayoutEffect(() => {
    const newElements = Array.from(containerRef.current?.querySelectorAll<HTMLElement>(selector) ?? defaultArray)
    // careful to avoid infinite rerendering loop
    // this works because the tasklist containers are preserved when we insert the tasklist
    setElements(oldElements => (arraysEqual(oldElements, newElements) ? oldElements : newElements))
  }, [verifiedHTML, containerRef, selector])

  return elements
}
