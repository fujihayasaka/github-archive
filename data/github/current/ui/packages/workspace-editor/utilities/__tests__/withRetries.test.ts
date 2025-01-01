// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {AggregateError, AssertionError, BaseError, CancellationError} from '../../errors'
import {assert, assertDefined} from '../asserts'
import {randomInt} from '../random-int'
import {wait} from '../wait'
import {withRetries} from '../with-retries'

// An error type for testing purposes.
class TestError extends BaseError {
  constructor(...args: ConstructorParameters<typeof BaseError>) {
    super(...args)
    this.name = 'TestError'
  }

  public override readonly errorType = 'TestError'
}

// time tollerance in milliseconds, bump up if tests are flaky
// due to race condition issues
const TIME_TOLLERANCE_MS = 10

/**
 * Tests to add:
 *  - test the `isAggregateError` option - if `false` the utility should throw the last error
 *    instead of `AggregateError`, for all(or many) throwing scenarious
 *  - test that `retries` options provided is `>= 0` and is a strictly defined number(e.g., not
 *    a `NaN` or `Infinity`)
 *  - test that `retryDelayMs` options provided is `>= 0` and is a strictly defined number(e.g., not
 *    a `NaN` or `Infinity`)
 *  - test that the utility `immediately` throws if a cancelled `CancellationToken` is provided
 *  - test provided `CancellationToken` is checked before every retry
 */

describe('withRetries', () => {
  beforeEach(() => {
    jest.useFakeTimers({doNotFake: []})
  })

  afterEach(() => {
    jest.useRealTimers()
  })

  it('should retry `2` times by default and throw `AggregateError`', async () => {
    const testFunction = jest.fn()

    let mainError: AggregateError | undefined

    try {
      await withRetries(async () => {
        testFunction()

        jest.runAllTimersAsync()

        throw new Error('Uggh ohh.')
      })
    } catch (error) {
      assert(error instanceof AggregateError, 'Expected error to be an instance of AggregateError.')

      mainError = error as AggregateError
    }

    expect(mainError).toBeInstanceOf(AggregateError)
    assertDefined(mainError, 'Main error not found.')

    expect(mainError.errors.length).toBe(3)
    expect(testFunction).toHaveBeenCalledTimes(3)
  })

  it('should retry `N` times and throw `AggregateError`', async () => {
    const testFunction = jest.fn()

    const N = randomInt(10, 1)

    let mainError: AggregateError | undefined

    try {
      await withRetries(
        () => {
          testFunction()

          jest.runAllTimersAsync()

          throw new Error('Ooops.')
        },
        {
          retries: N,
        },
      )
    } catch (error) {
      assert(error instanceof AggregateError, 'Expected error to be an instance of AggregateError.')

      mainError = error as AggregateError
    }

    expect(mainError).toBeInstanceOf(AggregateError)
    assertDefined(mainError, 'Main error not found.')

    expect(mainError.errors.length).toBe(N + 1)
    expect(testFunction).toHaveBeenCalledTimes(N + 1)
  })

  it('should retry `N` times with `retryDelayMs` delay inbetween', async () => {
    const testFunction = jest.fn()

    const N = randomInt(10, 1)
    const retryDelayMs = randomInt(50, 5)

    let mainError: AggregateError | undefined

    let startTime = performance.now()

    try {
      await withRetries(
        retriesLeft => {
          const attemptNumber = N - retriesLeft
          // validate that this callback is called the correct number of times
          expect(testFunction).toHaveBeenCalledTimes(attemptNumber)

          // validate the delay between retries, excluding on the first call
          // since the first call is immediate
          if (attemptNumber > 0) {
            const elapsedTime = performance.now() - startTime
            const timeDelta = elapsedTime - retryDelayMs

            assert(
              // elapsedTime can only be equal or slightly larger than
              // the actual retry delay
              timeDelta >= 0 && timeDelta <= TIME_TOLLERANCE_MS,
              new TestError(
                `Expected delay of about ${retryDelayMs}-${
                  retryDelayMs + TIME_TOLLERANCE_MS
                }ms, got ${elapsedTime}ms instead.`,
              ),
            )
            startTime = performance.now()
          }

          testFunction()
          jest.runAllTimersAsync()

          throw new Error('Oh my.')
        },
        {
          retries: N,
          retryDelayMs,
          shouldStopRetries: (error: Error) => {
            // for testing purposes only, used to detect the retry delay issues
            // inside the main callback of the `withRetries()` utility
            if (error instanceof TestError) {
              throw error
            }

            return false
          },
        },
      )
    } catch (error) {
      // for testing purposes only, used to detect the retry delay issues
      // inside the main callback of the `withRetries()` utility
      if (error instanceof TestError) {
        throw error
      }

      assert(error instanceof AggregateError, 'Expected error to be an instance of AggregateError.')
      mainError = error as AggregateError
    }

    expect(mainError).toBeInstanceOf(AggregateError)
    assertDefined(mainError, 'Main error not found.')

    expect(mainError.errors.length).toBe(N + 1)
    expect(testFunction).toHaveBeenCalledTimes(N + 1)
  })

  it('should return success value if one of the attempts succeeds', async () => {
    const testFunction = jest.fn()
    // a random success value to return
    const successValue = randomInt(1024, 8)
    // total number of retries
    const N = randomInt(10, 3)
    // retry number at which the success value should be returned
    const succeedsAt = randomInt(N, 0)

    const result = await withRetries(
      async retriesLeft => {
        const attemptNumber = N - retriesLeft
        // validate that this callback is called the correct number of times
        expect(testFunction).toHaveBeenCalledTimes(attemptNumber)

        if (attemptNumber === succeedsAt) {
          return successValue
        }

        testFunction()

        jest.runAllTimersAsync()

        throw new Error('Uggh ohh!')
      },
      {retries: N},
    )

    expect(testFunction).toHaveBeenCalledTimes(succeedsAt)
    expect(result).toBe(successValue)
  })

  it('should return success value if one of the attempts succeeds with retry delay', async () => {
    const testFunction = jest.fn()
    // a random success value to return
    const successValue = randomInt(1024, 8)
    // total number of retries
    const N = randomInt(10, 3)
    // retry number at which the success value should be returned
    const succeedsAt = randomInt(N, 0)
    // delay before each retry attempt, milliseconds
    const retryDelayMs = randomInt(50, 5)

    let startTime = performance.now()

    const result = await withRetries(
      async retriesLeft => {
        const attemptNumber = N - retriesLeft

        // validate that this callback is called the correct number of times
        expect(testFunction).toHaveBeenCalledTimes(attemptNumber)

        // validate the delay between retries, excluding on the first call
        // since the first call is immediate
        if (attemptNumber > 0) {
          const elapsedTime = performance.now() - startTime
          const timeDelta = elapsedTime - retryDelayMs

          assert(
            // elapsedTime can only be equal or slightly larger than
            // the actual retry delay
            timeDelta >= 0 && timeDelta <= TIME_TOLLERANCE_MS,
            new TestError(
              `Expected delay of about ${retryDelayMs}-${
                retryDelayMs + TIME_TOLLERANCE_MS
              }ms, got ${elapsedTime}ms instead.`,
            ),
          )
          startTime = performance.now()
        }

        if (attemptNumber === succeedsAt) {
          return successValue
        }

        testFunction()

        jest.runAllTimersAsync()

        throw new Error('Uggh ohh!')
      },
      {
        retries: N,
        retryDelayMs,
        shouldStopRetries: error => {
          // for testing purposes only, used to detect the retry delay issues
          // inside the main callback of the `withRetries()` utility
          if (error instanceof TestError) {
            throw error
          }

          return false
        },
      },
    )

    expect(testFunction).toHaveBeenCalledTimes(succeedsAt)
    expect(result).toBe(successValue)
  })

  it('should stop retries if `CancellationError` thrown', async () => {
    const testFunction = jest.fn()
    // total number of retries
    const N = randomInt(10, 3)
    // retry number at which should throw an error
    const throwsAt = randomInt(N, 0)

    let mainError: AggregateError | undefined

    try {
      await withRetries(
        async retriesLeft => {
          const attemptNumber = N - retriesLeft
          // validate that this callback is called the correct number of times
          expect(testFunction).toHaveBeenCalledTimes(attemptNumber)

          testFunction()

          if (attemptNumber === throwsAt) {
            throw new CancellationError('Something got cancelled somewhere.')
          }

          jest.runAllTimersAsync()

          throw new Error('Ohh la la!')
        },
        {
          retries: N,
        },
      )
    } catch (error) {
      assert(error instanceof AggregateError, 'Expected error to be an instance of AggregateError.')
      mainError = error as AggregateError
    }

    expect(mainError).toBeInstanceOf(AggregateError)
    assertDefined(mainError, 'Main error not found.')
    expect(mainError.message).toBe('Something got cancelled somewhere.')
    expect(mainError.lastError?.message).toBe('Something got cancelled somewhere.')
    expect(mainError.lastError).toBeInstanceOf(CancellationError)

    // initial call + number of retries
    expect(testFunction).toHaveBeenCalledTimes(1 + throwsAt)
  })

  it('should stop retries if `CancellationError` thrown and `shouldStopRetries` always returns `false`', async () => {
    const testFunction = jest.fn()
    // total number of retries
    const N = randomInt(10, 3)
    // retry number at which should throw an error
    const throwsAt = randomInt(N, 0)

    let mainError: AggregateError | undefined

    try {
      await withRetries(
        async retriesLeft => {
          const attemptNumber = N - retriesLeft
          // validate that this callback is called the correct number of times
          expect(testFunction).toHaveBeenCalledTimes(attemptNumber)

          testFunction()

          if (attemptNumber === throwsAt) {
            throw new CancellationError('Something got cancelled somewhere.')
          }

          jest.runAllTimersAsync()

          throw new Error('Keyboard is not found. Please press any key to continue.')
        },
        {
          retries: N,
          shouldStopRetries: () => false,
        },
      )
    } catch (error) {
      assert(error instanceof AggregateError, 'Expected error to be an instance of AggregateError.')
      mainError = error as AggregateError
    }

    expect(mainError).toBeInstanceOf(AggregateError)
    assertDefined(mainError, 'Main error not found.')
    expect(mainError.message).toBe('Something got cancelled somewhere.')
    expect(mainError.lastError?.message).toBe('Something got cancelled somewhere.')
    expect(mainError.lastError).toBeInstanceOf(CancellationError)

    // initial call + number of retries
    expect(testFunction).toHaveBeenCalledTimes(1 + throwsAt)
  })

  describe('shouldStopRetries', () => {
    it('should stop retrying if `true` is returned', async () => {
      const testFunction = jest.fn()
      // total number of retries
      const N = randomInt(10, 3)
      // retry number at which should stop retrying
      const stopAtRetryNumber = randomInt(N, 0)

      let mainError: AggregateError | undefined

      try {
        await withRetries(
          async retriesLeft => {
            const attemptNumber = N - retriesLeft
            // validate that this callback is called the correct number of times
            expect(testFunction).toHaveBeenCalledTimes(attemptNumber)

            testFunction()

            jest.runAllTimersAsync()

            throw new Error('Uggh gosh!')
          },
          {
            retries: N,
            shouldStopRetries: (_, retriesLeft) => {
              const failedAttemptNumber = N - retriesLeft
              if (failedAttemptNumber === stopAtRetryNumber) {
                return true
              }

              return false
            },
          },
        )
      } catch (error) {
        assert(error instanceof AggregateError, 'Expected error to be an instance of AggregateError.')
        mainError = error as AggregateError
      }

      expect(mainError).toBeInstanceOf(AggregateError)
      assertDefined(mainError, 'Main error not found.')

      // initial call + number of retries
      expect(testFunction).toHaveBeenCalledTimes(1 + stopAtRetryNumber)
    })

    it('throws if an error is thrown inside the callback', async () => {
      const testFunction = jest.fn()
      // total number of retries
      const N = randomInt(10, 3)
      // retry number at which should throw an error
      const throwsAt = randomInt(N - 1, 0)

      let mainError: AssertionError | undefined

      try {
        await withRetries(
          async retriesLeft => {
            const attemptNumber = N - retriesLeft
            // validate that this callback is called the correct number of times
            expect(testFunction).toHaveBeenCalledTimes(attemptNumber)

            testFunction()

            jest.runAllTimersAsync()

            throw new Error('Uggh gosh!')
          },
          {
            retries: N,
            shouldStopRetries: (_, retriesLeft) => {
              const failedAttemptNumber = N - retriesLeft
              if (failedAttemptNumber === throwsAt) {
                throw new AssertionError('WAT!')
              }

              return false
            },
          },
        )
      } catch (error) {
        assert(error instanceof AssertionError, 'Expected error to be an instance of AssertionError.')
        mainError = error as AssertionError
      }

      expect(mainError).toBeInstanceOf(AssertionError)
      assertDefined(mainError, 'Main error not found.')
      expect(mainError.message).toBe('WAT!')

      // initial call + number of retries
      expect(testFunction).toHaveBeenCalledTimes(1 + throwsAt)
    })

    it('should await on the callback', async () => {
      const testFunction = jest.fn()
      // a random success value to return
      const successValue = `some-value-${randomInt(1024, 8)}`
      // total number of retries
      const N = randomInt(10, 3)
      // retry number at which the success value should be returned
      const succeedsAt = randomInt(N, 0)
      // delay before each retry attempt, milliseconds
      const retryDelayMs = randomInt(50, 5)
      // additional retry delay to use inside the `shouldStopRetries` function
      const additionalRetryDelayMs = randomInt(50, 5)

      let startTime = performance.now()

      const result = await withRetries(
        async retriesLeft => {
          const attemptNumber = N - retriesLeft

          // validate that this callback is called the correct number of times
          expect(testFunction).toHaveBeenCalledTimes(attemptNumber)

          // validate the delay between retries, excluding on the first call
          // since the first call is immediate
          if (attemptNumber > 0) {
            const elapsedTime = performance.now() - startTime
            const timeDelta = elapsedTime - (retryDelayMs + additionalRetryDelayMs)

            assert(
              // elapsedTime can only be equal or slightly larger than
              // the actual retry delay
              timeDelta >= 0 && timeDelta <= TIME_TOLLERANCE_MS,
              new TestError(
                `Expected delay of about ${retryDelayMs}-${
                  retryDelayMs + TIME_TOLLERANCE_MS
                }ms, got ${elapsedTime}ms instead.`,
              ),
            )
            startTime = performance.now()
          }

          if (attemptNumber === succeedsAt) {
            return successValue
          }

          testFunction()

          jest.runAllTimersAsync()

          throw new Error('Uggh ohh!')
        },
        {
          retries: N,
          retryDelayMs,
          shouldStopRetries: async error => {
            // for testing purposes only, used to detect the retry delay issues
            // inside the main callback of the `withRetries()` utility
            if (error instanceof TestError) {
              throw error
            }

            // wait for additional delay before each retry
            await wait(additionalRetryDelayMs)

            return false
          },
        },
      )

      expect(testFunction).toHaveBeenCalledTimes(succeedsAt)
      expect(result).toBe(successValue)
    })
  })
})
