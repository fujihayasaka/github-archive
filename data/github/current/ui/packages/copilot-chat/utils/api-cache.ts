import type {APIResult} from './copilot-chat-types'

/**
 * Caches results of API calls based on the parameters. Ensures that only one request is dispatched for the same parameters.
 */
export class ApiCache<TResult, TParams extends string[]> {
  private readonly separator = '-!-'
  private cache = new Map<string, Promise<APIResult<TResult>>>()

  private declare fetchFn: (...params: TParams) => Promise<APIResult<TResult>>

  public constructor(fetchFn: (...params: TParams) => Promise<APIResult<TResult>>) {
    this.fetchFn = fetchFn
  }

  public async get(...params: TParams): Promise<APIResult<TResult>> {
    const key = params.join(this.separator)
    const cached = this.cache.get(key)
    if (cached) {
      return cached
    } else {
      const promise = this.fetchFn(...params)
      this.cache.set(key, promise)
      const result = await promise
      if (!result.ok) {
        this.cache.delete(key)
      }
      return promise
    }
  }
}
