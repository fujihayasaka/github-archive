import {AssertionError} from '../../../errors'
import {assert, assertDefined} from '../../asserts'

describe('assert', () => {
  it('should not throw if `condition` is `true`', async () => {
    const errorMessage = 'Oops something happened.'
    expect(() => {
      assert(true, errorMessage)
    }).not.toThrow()
  })

  it('should throw if `condition` is `false`', async () => {
    const errorMessage = 'Oops something happened.'
    expect(() => {
      assert(false, errorMessage)
    }).toThrow(errorMessage)
  })

  it('should throw assertion error by default', async () => {
    let thrownError: AssertionError | undefined
    try {
      assert(false, 'Oh my!')
    } catch (e) {
      thrownError = e as AssertionError
    }

    expect(thrownError).toBeInstanceOf(AssertionError)
    assertDefined(thrownError, 'Must throw an error.')

    expect(thrownError.message).toEqual('Oh my!')
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
      assert(false, error)
    } catch (e) {
      thrownError = e
    }

    expect(thrownError instanceof TestError).toEqual(true)
    const testError = thrownError as TestError
    expect(testError.message).toEqual(errorMessage)
    expect(testError.message).toEqual(error.message)
  })
})
