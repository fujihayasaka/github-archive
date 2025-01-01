export function createCancelableFunction<T, TArgs extends unknown[]>(
  fn: (...args: [...TArgs, AbortSignal]) => Promise<T>,
) {
  let abortController: AbortController | null = null

  return async (...args: TArgs): Promise<T> => {
    // Cancel previous request if exists
    if (abortController) {
      abortController.abort()
    }

    // Create new abort controller for this request
    abortController = new AbortController()

    try {
      // Pass abort signal to the wrapped function
      const result = await fn(...args, abortController.signal)
      abortController = null
      return result
    } catch (error) {
      // Clean up controller reference
      abortController = null

      // Rethrow if it's not an abort error
      if (error instanceof Error && error.name !== 'AbortError') {
        throw error
      }

      throw new Error('Request was canceled')
    }
  }
}
