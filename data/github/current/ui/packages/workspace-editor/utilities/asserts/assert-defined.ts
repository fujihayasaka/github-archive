import {AssertionError} from '../../errors'

/**
 * Asserts that a provided value is `defined`(not `null` or `undefined`),
 * throwing an error with the provided error or error message otherwise.
 *
 * ## Examples
 *
 * ```typescript
 * // an assert with an error message
 * assertDefined('some value', 'String constant is not defined.')
 *
 * // (throws!) an assert with an error message
 * assertDefined(null, new Error('Should throw this error.'))
 * ```
 */
export function assertDefined<T>(object: T, error: string | NonNullable<Error>): asserts object is NonNullable<T> {
  // Note: the `!=` takes into account both `null` and `undefined`
  if (object == null) {
    const errorToThrow = typeof error === 'string' ? new AssertionError(error) : error

    throw errorToThrow
  }
}
