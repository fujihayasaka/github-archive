// In some distant future, like 2025, we can remove this function and instead
// rely on the `Promise.withResolvers` function to be available in all
// versions of Node and browsers.
// Then, we can stop importing this and just use `Promise.withResolvers` directly.

export function withResolvers<T>() {
  const out = {} as {
    promise: Promise<T>
    resolve: (value: T | PromiseLike<T>) => void
    reject: (reason?: unknown) => unknown
  }
  out.promise = new Promise<T>((resolve, reject) => {
    out.resolve = resolve
    out.reject = reject
  })
  return out
}
