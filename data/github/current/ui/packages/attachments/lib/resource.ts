// JSResource shim

export type Resource<T> = {
  load(): Promise<T>
  read(): T
}

export function resource<T>(load: () => Promise<T>): Resource<T> {
  let value: T
  let promise: Promise<T> | null = null

  return {
    load() {
      if (!promise) {
        // eslint-disable-next-line github/no-then
        promise = load().then(v => {
          value = v
          return value
        })
      }
      return promise
    },
    read() {
      if (value) return value
      // eslint-disable-next-line @typescript-eslint/only-throw-error
      throw this.load()
    },
  }
}
