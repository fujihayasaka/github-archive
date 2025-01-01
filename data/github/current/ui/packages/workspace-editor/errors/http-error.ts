import {BaseError} from './base-error'

// List of non-retriable HTTP status codes.
const NON_RETRIABLE_HTTP_STATUS_CODES = [400, 401, 403, 404]

/**
 * Error thrown when an HTTP request failed.
 */
export class HttpError extends BaseError {
  public override readonly errorType: string = 'HttpError'

  constructor(
    // HTTP response status code.
    public readonly status: number,
    // HTTP response status text.
    public readonly statusText: string,
    // Additional error message to enhance the error contextual info.
    message: string = 'HTTP request failed',
  ) {
    super(`${message}: ${status} - ${statusText}`)
    this.name = 'HttpError'
  }

  // Create an `HttpError` instance from a provided response object.
  public static fromResponse(response: Response, message: string): HttpError {
    return new HttpError(response.status, response.statusText, message)
  }

  // Check if the provided response is retriable.
  public isRetriable(): boolean {
    return !NON_RETRIABLE_HTTP_STATUS_CODES.includes(this.status)
  }
}
