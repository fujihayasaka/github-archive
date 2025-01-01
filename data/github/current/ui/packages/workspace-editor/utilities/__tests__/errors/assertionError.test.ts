// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {AssertionError, BaseError} from '../../../errors'

describe('AssertionError', () => {
  it('should extend BaseError', () => {
    const error = new AssertionError()

    expect(error).toBeInstanceOf(BaseError)
    expect(error).toBeInstanceOf(Error)
  })

  it('should have correct error type', () => {
    const error = new AssertionError()

    expect(error.errorType).toBe('AssertionError')
  })

  it('should accept error message', () => {
    const error = new AssertionError('Something bad happened.')

    expect(error.errorType).toBe('AssertionError')
    expect(error.message).toBe('Something bad happened.')
    expect(error.errorCode).toBe(undefined)
    expect(error.stack).toBeDefined()
  })

  it('should accept error code', () => {
    const error = new AssertionError('Something else bad happened.', 21)

    expect(error.errorType).toBe('AssertionError')
    expect(error.message).toBe('Something else bad happened.')
    expect(error.errorCode).toBe(21)
    expect(error.stack).toBeDefined()
  })

  it('should accept error instance', () => {
    const genericError = new Error('Something unexpected happened.')
    const error = new AssertionError(genericError)

    expect(error.errorType).toBe('AssertionError')
    expect(error.message).toBe('Something unexpected happened.')
    expect(error.errorCode).toBe(undefined)
    expect(error.stack).toBe(genericError.stack)
  })
})
