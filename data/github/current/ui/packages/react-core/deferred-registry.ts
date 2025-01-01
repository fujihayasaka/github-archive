// Remove this line and replace `withResolvers` with `Promise.withResolvers`
// the day we know no polyfilling is necessary.
import {withResolvers} from '@github-ui/promise-with-resolvers-polyfill'

export class DeferredRegistry<T> {
  #registrationEntries = new Map<
    string,
    {
      promise: Promise<T>
      resolve: (value: T | PromiseLike<T>) => void
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      reject: (reason?: any) => void
    }
  >()

  public register(name: string, registration: T) {
    const entry = this.#registrationEntries.get(name)
    if (entry) {
      entry.resolve(registration)
    } else {
      const registrationWithResolvers = withResolvers<T>()
      registrationWithResolvers.resolve(registration)
      this.#registrationEntries.set(name, registrationWithResolvers)
    }
  }

  public getRegistration(name: string): {
    promise: Promise<T>
    resolve: (value: T | PromiseLike<T>) => void
  } {
    const registration = this.#registrationEntries.get(name)
    if (registration) {
      return registration
    }

    const registrationWithResolvers = withResolvers<T>()
    this.#registrationEntries.set(name, registrationWithResolvers)
    return registrationWithResolvers
  }
}
