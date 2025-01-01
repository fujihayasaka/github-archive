export function createRetryWithBackoff<TArgs extends unknown[], TReturn>(
  fn: (...args: TArgs) => Promise<TReturn>,
  maxRetries: number,
  baseDelay: number = 1000,
  shouldRetry?: (error: unknown) => boolean,
): (...args: TArgs) => Promise<TReturn> {
  return async function retryWrapper(...args: TArgs): Promise<TReturn> {
    let retryCount = 0

    while (true) {
      try {
        const result = await fn(...args)
        retryCount = 0

        return result
      } catch (error) {
        if (shouldRetry && !shouldRetry(error)) {
          throw error
        }

        if (retryCount >= maxRetries) {
          throw error
        }

        retryCount++

        const backoff = baseDelay * Math.pow(2, retryCount)
        const jitter = Math.random() * 0.1 * backoff
        const delay = backoff + jitter

        await new Promise(resolve => setTimeout(resolve, delay))
      }
    }
  }
}
