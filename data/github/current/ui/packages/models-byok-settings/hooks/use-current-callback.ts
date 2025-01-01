import {useCallback, useRef} from 'react'

/**
 * A helper hook that keeps a stable reference to a function, that when invoked
 * will always call the latest version of the callback provided.
 * This is useful when you have a callback that is used in a dependency array, or prop
 * to another component that may expect a stable reference, or a callback that is not stable.
 *
 * @example
 *
 * ```tsx
 * function MyComponent(props) {
 *   const callback = useCurrentCallback(props.unstableCallback)
 *   return <Button onClick={callback}>Click me</Button>
 * }
 * ```
 */
// `: any` here gives us the ability to type narrow, where `: unknown` would not
// eg: const cb = useCurrentCallback((foo: string) => boolean)
//          ^? (foo: string) => boolean
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function useCurrentCallback<T extends (...args: any[]) => any>(callback?: T | null): T {
  const currentCallback = useRef<T | null | undefined>(callback)
  currentCallback.current = callback
  // eslint-disable-next-line @typescript-eslint/no-unsafe-return
  return useCallback((...args: Parameters<T>) => currentCallback.current?.(...args), []) as T
}
