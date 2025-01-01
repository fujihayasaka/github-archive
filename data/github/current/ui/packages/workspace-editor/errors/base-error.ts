/**
 * Base error, all errors should extended it and specify new `errorType`.
 *
 * The error has:

 *  - `errorType` - identifies the error type, every error that inherits from
 *      this one, override the `errorType` with its own value.
 * - `errorCode` - error code (number) for the specific error case.
 * - `originalErrorType` - if an error with an `errorType`/`errorCode` is
 *     "wrapped" with this error, the data is reserved in the `originalErrorType`
 *     so we don't lose the original context.
 * - `stack`[optional] - error stack trace. If an error is wrapped with this
 *     error, the stack is copied over.
 */
export class BaseError extends Error {
  public readonly errorType: string = 'BaseError'

  public readonly originalErrorType?: string

  public readonly originalError?: Error

  constructor(
    error?: Error | string,
    public readonly errorCode?: number,
  ) {
    super(typeof error === 'string' ? error : error?.message)
    this.name = 'BaseError'

    if (error instanceof Error) {
      this.originalError = error
      this.stack = error.stack
      this.originalErrorType = this.getOriginalErrorCode(error)

      this.errorCode = errorCode ?? (error as BaseError).errorCode
    }
  }

  private getOriginalErrorCode(error: Error) {
    const {errorType = '[no-type]', errorCode = '[no-code]'} = error as BaseError

    return `[${errorType}:${errorCode}]`
  }
}
