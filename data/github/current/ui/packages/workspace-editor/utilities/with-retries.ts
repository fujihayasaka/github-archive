import {AggregateError, AssertionError, CancellationError} from '../errors'
import {assert} from './asserts/assert'
import {wait} from './wait'

// Type definition of the main callback function.
type TMainCallback<K> = (retriesLeft: number) => Promise<K> | K

// Type definition of the `shouldStopRetries()` callback function.
type TShouldStopRetryCallback = (error: Error, retriesLeft: number) => Promise<boolean> | boolean

// Type definition of the `onBeforeRetry()` callback function.
type TOnBeforeRertyCallback = (error: Error, retriesLeft: number) => Promise<void> | void

export interface IWithRetriesOptions {
  // Number of retries to make.
  // Defaults to `0`.
  // Note: total number of function calls if all calls are failing
  //       is `retries` + 1 (e.g., initial call plus the retries).
  retries: number
  // Delay before each retry attempt, milliseconds.
  // Defaults to `0`.
  retryDelayMs: number
  // Factor to increase the `retryDelayMs` between each retry attempt.
  // Defaults to `1.0`.
  exponentialBackoffFactor: number
  // Timeout for the entire retry sequence, milliseconds.
  // Defaults to `Number.MAX_VALUE`.
  timeoutMs: number
  // Optional callback to notify the `withRetries` function that
  // it should stop further retry attempts. Useful to define a
  // bail-out logic for the known fatal errors. For example, if
  // the `withRetries` utility is used to retry the HTTP requests,
  // it won't make sense to retry for certain HTTP status codes -
  // the codes alike to 401, 404, 400, etc.
  // Can also be used to add an extra delay before the next retry.
  //
  // Throwing an error inside the callback results in stopping entire
  // retry sequence and the original `withRetries` call throwing.
  shouldStopRetries: TShouldStopRetryCallback
  // Optional callback to invoke before each retry attempt.
  // Useful to inspect or trace the last error, or to add an extra
  // delay before the next retry attempt.
  //
  // Throwing an error inside the callback results in stopping entire
  // retry sequence and the original `withRetries` call throwing.
  onBeforeRetry: TOnBeforeRertyCallback
  // Defines if the retry error sequence should be collected into
  // a single `AggregateError` or the last error should be thrown.
  // Defaults to `true`.
  isAggregateError: boolean
  /**
   * Comment out the cancellation token logic for now because of
   * npm packages installation issues in dotcom.
   * (needs `CancellationToken` from the `vscode-jsonrpc` package)
   */
  // // Optional cancellation token to cancel the retry sequence.
  // cancellationToken?: CancellationToken
}

/**
 * Option defaults.
 */
const WITH_RETRIES_DEFAULTS: IWithRetriesOptions = {
  // 1 call + 2 retries = 3 calls total
  retries: 2,
  // no delay by default
  retryDelayMs: 0,
  // no exponential backoff by default
  exponentialBackoffFactor: 1.0,
  // no timeout by default
  timeoutMs: Number.MAX_VALUE,
  // no-op `shouldStopRetries` callback
  shouldStopRetries: () => {
    return false
  },
  // no-op `onBeforeRetry` callback
  onBeforeRetry: () => {},
  // should throw the last error instead of `AggregateError`
  isAggregateError: true,
}

/**
 * Utility to run an asynchronous function with a number of retries.
 * Can be used as a polling helper if the `retryDelayMs` is specified.
 *
 * Throws `AggregateError` with all the thrown `errors` that we risen
 * during the retry attempts. The `last` property of the `AggregateError`
 * is the last throw error in the sequence.
 *
 * - Returns the return value of the last `fn` call. If the last `fn` call
 *   throws, the `AggregateError` is thrown.
 *
 * - Throw `CancellationError` inside the `fn` callback to cancel the retries.
 *
 * - If the `CancellationToken` is passed and cancellation is requested,
 *   the `AggregateError` is thrown, with the `CancellationError` error
 *   as the last in the list.
 *
 * - `shouldStopRetries`, optional callback meant for implementing an early bail-out
 *   from the retry loop. It receives an `error` from the last failed retry attempt
 *   and should return a `boolean` indicating if we should stop the retry loop.
 *   Helpful for the cases when the error thrown is known to be fatal, so doesn't
 *   make sense to continue the remaining retries.
 */
export const withRetries = async <K, T extends TMainCallback<K> = TMainCallback<K>>(
  // the main callback function to run with retries
  fn: T,
  // utility options
  options: Partial<IWithRetriesOptions> = {},
  // mostly used internally, but can be also used to pass and existing
  // `AggregateError` to continue amassing possible errors in it
  aggregateError: AggregateError = new AggregateError(),
): Promise<K> => {
  /**
   * Extend the options with defaults.
   */
  const opts: IWithRetriesOptions = {
    ...WITH_RETRIES_DEFAULTS,
    ...options,
  }

  const {
    retries,
    retryDelayMs,
    exponentialBackoffFactor,
    timeoutMs,
    shouldStopRetries,
    onBeforeRetry,
    isAggregateError,
  } = opts

  /**
   * Make sure a number of retries left. In theory should never
   * go in this case, unless wrong `retries` option was passed.
   *
   * Throwing the `AggregateError` with a single `AssertionError`
   * for consistency.
   */
  const assertionError = new AssertionError('Retries should have at least zero retries.')

  // if `isAggregateError` option set, throw the error itself,
  // to be consistent with the logic inside the catch block
  assert(retries > -1, !isAggregateError ? assertionError : aggregateError.cloneWithErrors(assertionError))

  let retryAttempt = 0
  while (Date.now() < timeoutMs && retryAttempt <= retries) {
    const retriesRemaining = retries - retryAttempt
    try {
      /**
       * Comment out the cancellation token logic for now because of
       * npm packages installation issues in dotcom.
       */
      // // check that the cancellation is not requested yet on the `CancellationToken`
      // assert(!cancellationToken?.isCancellationRequested, new CancellationError('Cancelled by the CancellationToken.'))

      // invoke the main procedure callback
      return (await fn(retriesRemaining)) as K
    } catch (e) {
      // make sure we have an `Error` instance
      const error = e instanceof Error ? e : new Error(`[unknown error type] ${e}`)
      // copy the original stack trace if available
      if ((e as Error).stack) {
        error.stack = (e as Error).stack
      }

      // if the invocation fails, add the error to the aggregate error list
      aggregateError.addErrors(error)

      /**
       * Check if we should stop retrying prematurely.
       * Helpful in the cases hwen the error throw is indicative of a
       * fatal failure, hence does not make sence to retry anymore.
       *
       * The `shouldStopRetries()` callback is invoked only if some retry attemps left, and
       * the call is awaited, to enable adding delays in the callback. For example, if an error
       * is of well-known type, an extra delay could be applied for that error before retrying again.
       */
      if (retriesRemaining > 0 && (await shouldStopRetries(error, retriesRemaining))) {
        return aggregateError.throw(!isAggregateError)
      }

      // if cancelled inside the callback, stop retrying
      if (error instanceof CancellationError) {
        return aggregateError.throw(!isAggregateError)
      }

      /**
       * Comment out the cancellation token logic for now because of
       * npm packages installation issues in dotcom.
       */
      // // heck that the cancellation is not requested yet on the `CancellationToken`
      // const cancellationError = new CancellationError('CancellationToken is cancelled after retry.')
      // assert(
      //   !cancellationToken?.isCancellationRequested,
      //   // throw either `AggregateError` with the `CancellationError` at the end,
      //   // or the `CancellationError` itself (if the `isAggregateError` is set)
      //   !isAggregateError ? cancellationError : aggregateError.cloneWithErrors(cancellationError),
      // )

      // wait for (`retryDelayMs` * any potential exponential backoff) milliseconds before making another retry
      const delay = retryDelayMs * Math.pow(exponentialBackoffFactor, retryAttempt)
      await wait(delay)
      retryAttempt++

      /**
       * Invoke the `onBeforeRetry` callback before starting
       * another retry attempt.
       *
       * Similarly to rhe `shouldStopRetries()` callback above, the call is awaited to
       * allow for asynchronous code or additional delays inside the callback.
       */
      await onBeforeRetry(error, retries)
    }
  }

  /**
   * No more retries or timed out, throw the result error.
   * - by default, throw the  aggregate error that contains
   *   the list of all errors thrown during the retries.
   * - if `isAggregateError` set to `false`, throw the last
   *  error in the list.
   */
  return aggregateError.throw(!isAggregateError)
}
