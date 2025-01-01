/**
 * Returns a function that waits for rapid/repeated calls to stop, before calling a wrapped function.
 * @param fn Wrapped function
 * @param delay Period, in milliseconds, within which repeated calls are ignored
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function debounce<F extends (..._args: any[]) => any>(
  fn: F,
  delay: number,
): (..._args: Parameters<typeof fn>) => void {
  let timeoutId: ReturnType<typeof setTimeout>
  return function (...args: Parameters<typeof fn>): void {
    if (timeoutId) {
      clearTimeout(timeoutId)
    }
    timeoutId = setTimeout(() => {
      fn(...args)
    }, delay)
  }
}
