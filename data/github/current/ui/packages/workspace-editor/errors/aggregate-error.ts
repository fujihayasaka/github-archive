import {BaseError} from './base-error'

/**
 * Aggregate error represents a number errors accumulated into a single error instance.
 * It is useful for tracking collection of nested errors, or sequence of errors generated
 * during multiple retry attempts.
 */
export class AggregateError extends BaseError {
  public override readonly errorType: string = 'AggregateError'

  constructor(
    private readonly ownMessage?: string,
    errorCode?: number,
  ) {
    // if `ownMessage` is passed to the parent constructor, it will break
    // the `message` getter defined on this class, so we pass `undefined`
    super(undefined, errorCode)
    this.name = 'AggregateError'
  }

  /**
   * The errors list as a private reference.
   */
  private readonly errorsReference: Error[] = []

  /**
   * Get a copy aggregate error list.
   */
  public get errors(): Error[] {
    return [...this.errorsReference]
  }

  /**
   * Add errors to the aggregate error list.
   */
  public addErrors(...errors: Error[]): this {
    this.errorsReference.push(...errors)
    return this
  }

  /**
   * Creates new `AggregateError` copy from the current one and adds the errors.
   */
  public cloneWithErrors(...errors: Error[]): AggregateError {
    const newError = new AggregateError(this.ownMessage, this.errorCode)

    newError.addErrors(...this.errors, ...errors)

    return newError
  }

  /**
   * Return the last error in the error sequence.s
   */
  public get lastError(): Error | undefined {
    const lastErrorIndex = this.errorsReference.length - 1

    return this.errorsReference[lastErrorIndex]
  }

  /**
   * Function to throw either the current `AggregateError` or,
   * if the `isThrowLastError` is `true`, the last error in
   * the aggregate error list.
   */
  public throw(isThrowLastError: boolean): never {
    if (isThrowLastError && this.lastError) {
      throw this.lastError
    }

    throw this
  }

  /**
   * Get error message.
   */
  public override get message(): string {
    if (this.ownMessage && this.lastError) {
      return `${this.ownMessage} ${this.lastError.message}`
    }

    // if there is no own message but a last error, return the last error message
    if (this.lastError) {
      return this.lastError.message
    }

    // if there is an own message but no last error, return the own message
    return this.ownMessage || ''
  }
}
