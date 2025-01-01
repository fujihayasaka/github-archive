import type React from 'react'

/**
 * Merges multiple refs into a single ref callback.
 * This allows assigning a single DOM node or component instance to multiple refs.
 * Useful for combining forwarded refs with internal refs.
 * Filters out null or undefined refs.
 *
 * @example
 *
 * ```jsx
 * const MyComponent = React.forwardRef((props, ref) => {
 *   const internalRef = React.useRef(null);
 *   const mergedRef = mergeRefs([ref, internalRef]);
 *   return <div ref={mergedRef}>Hello</div>;
 * });
 *
 * function MyOtherComponent() {
 *   const myComponentRef = React.useRef(null);
 *   return <MyComponent ref={myComponentRef} />
 * }
 * ```
 */
export function mergeRefs<T>(refs: Array<React.Ref<T> | null | undefined>): React.RefCallback<T> {
  return (value: T | null) => {
    for (const ref of refs) {
      if (typeof ref === 'function') {
        ref(value)
      } else if (ref != null) {
        // Handle RefObject
        // Assign to the 'current' property. Cast needed due to readonly type.
        // This is a common pattern for merging refs.
        ;(ref as React.MutableRefObject<T | null>).current = value
      }
    }
  }
}
