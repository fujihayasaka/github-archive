import {BaseError} from './base-error'

/**
 * Error thrown when something is cancelled. Used by `Signal`.
 */
export class CancellationError extends BaseError {
  constructor(...args: ConstructorParameters<typeof BaseError>) {
    super(...args)
    this.name = 'CancellationError'
  }

  public override readonly errorType: string = 'CancellationError'
}
