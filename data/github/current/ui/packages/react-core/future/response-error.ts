/**
 * Stores a Response object within an Error, so that the application
 * can access the response when an error is thrown.
 *
 * For example, a `queryFn` can throw the error like so:
 *
 * if (!response.ok) throw new ResponseError(response.statusText, response)
 *
 * which should cause the Error to be thrown from within the loader.
 *
 * Then an ErrorBoundary can consume the route error and access the response, like so:
 *
 * const routeError = useRouteError()
 * const responseStatus = isResponseError(routeError) ? routeError.response.status : undefined
 *
 */
export class ResponseError extends Error {
  declare readonly response: Response
  constructor(message: string, response: Response) {
    super(message)
    this.response = response
    // Keep the prototype.name fixed even after minification.
    this.name = 'ResponseError'
  }
}

/**
 * Type guard for checking to see if a parameter is a ResponseError object
 */
export function isResponseError(e: unknown): e is ResponseError {
  return e instanceof ResponseError
}
