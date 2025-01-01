import {AssertionError} from '../../../errors'
import {assertDefined, assertNonEmptyArray} from '../../asserts'

describe('assertNonEmptyArray', () => {
  it('should not throw if `array` is non-empty #1', async () => {
    const array = [1]
    expect(() => {
      assertNonEmptyArray(array, 'Array must not be empty.')
    }).not.toThrow()
  })

  it('should not throw if `array` is non-empty #2', async () => {
    const array = [1, 2, 3]
    expect(() => {
      assertNonEmptyArray(array, 'Array must not be empty.')
    }).not.toThrow()
  })

  it('should throw if `array` is empty', async () => {
    const array: number[] = []
    expect(() => {
      assertNonEmptyArray(array, 'Array must not be empty.')
    }).toThrow('Array must not be empty.')
  })

  it('should throw assertion error by default', async () => {
    let thrownError: AssertionError | undefined
    try {
      assertNonEmptyArray([], 'Oh la la!')
    } catch (e) {
      thrownError = e as AssertionError
    }

    expect(thrownError).toBeInstanceOf(AssertionError)
    assertDefined(thrownError, 'Must throw an error.')

    expect(thrownError.message).toEqual('Oh la la!')
  })

  it('should throw provided error instance', async () => {
    class TestError extends Error {
      constructor(...args: ConstructorParameters<typeof Error>) {
        super(...args)
        this.name = 'TestError'
      }
    }

    const errorMessage = 'Oops something hapenned'
    const error = new TestError(errorMessage)

    let thrownError
    try {
      assertNonEmptyArray([], error)
    } catch (e) {
      thrownError = e
    }

    expect(thrownError instanceof TestError).toEqual(true)
    const testError = thrownError as TestError
    expect(testError.message).toEqual(errorMessage)
    expect(testError.message).toEqual(error.message)
  })
})
