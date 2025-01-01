import {BaseError} from './base-error'

/**
 * Error thrown when an assertion fails.
 */
export class AssertionError extends BaseError {
  constructor(...args: ConstructorParameters<typeof BaseError>) {
    super(...args)
    this.name = 'AssertionError'
  }

  public override readonly errorType: string = 'AssertionError'
}
