export class FileReference {
  constructor(public file: File) {}

  // NOTE: We just use a random UUID, to give React something to key for. Useful if we put files in a loop, or to
  // indicate that a React component is the same, and thus it's tree's can be reused.
  key = globalThis.crypto.randomUUID()

  #resource = resource<string>(async () => {
    return new Promise<string>((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = () => {
        resolve(reader.result as string)
      }
      reader.onerror = reject
      reader.readAsDataURL(this.file)
    })
  })

  get preview() {
    // NOTE: In the future, if the file is not an image, perhaps we can return a generic preview image
    return this.#resource.read()
  }

  get base64URI() {
    return this.#resource.load()
  }
}

// JSResource shim
function resource<T>(load: () => Promise<T>) {
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
