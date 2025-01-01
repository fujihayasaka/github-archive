// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {AssertionError} from '../../../errors'
import {assertDefined} from '../../asserts'

describe('assertDefined', () => {
  it('should not throw if `object` is defined (bool)', async () => {
    const errorMessage = 'Oops something happened.'
    expect(() => {
      assertDefined(true, errorMessage)
    }).not.toThrow()
  })

  it('should not throw if `object` is defined (number)', async () => {
    const errorMessage = 'Oops something happened.'
    expect(() => {
      assertDefined(5, errorMessage)
    }).not.toThrow()
  })

  it('should not throw if `object` is defined (zero)', async () => {
    const errorMessage = 'Oops something happened.'
    expect(() => {
      assertDefined(0, errorMessage)
    }).not.toThrow()
  })

  it('should not throw if `object` is defined (string)', async () => {
    const errorMessage = 'Oops something happened.'
    expect(() => {
      assertDefined('some string', errorMessage)
    }).not.toThrow()
  })

  it('should not throw if `object` is defined (empty string)', async () => {
    const errorMessage = 'Oops something happened.'
    expect(() => {
      assertDefined('', errorMessage)
    }).not.toThrow()
  })

  it('should throw if `object` is `null`', async () => {
    const errorMessage = 'Oops something happened.'
    expect(() => {
      assertDefined(null, errorMessage)
    }).toThrow(errorMessage)
  })

  it('should throw if `object` is `undefined`', async () => {
    const errorMessage = 'Oops something happened.'
    expect(() => {
      assertDefined(undefined, errorMessage)
    }).toThrow(errorMessage)
  })

  it('should throw assertion error by default', async () => {
    let thrownError: AssertionError | undefined
    try {
      assertDefined(null, 'Oh gosh!')
    } catch (e) {
      thrownError = e as AssertionError
    }

    expect(thrownError).toBeInstanceOf(AssertionError)
    assertDefined(thrownError, 'Must throw an error.')

    expect(thrownError.message).toEqual('Oh gosh!')
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
      assertDefined(null, error)
    } catch (e) {
      thrownError = e
    }

    expect(thrownError instanceof TestError).toEqual(true)
    const testError = thrownError as TestError
    expect(testError.message).toEqual(errorMessage)
    expect(testError.message).toEqual(error.message)
  })
})
