// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {BaseError} from '../../../errors'

describe('BaseError', () => {
  it('should extend Error class', () => {
    const error = new BaseError()

    expect(error).toBeInstanceOf(Error)
  })

  it('should have the correct error type', () => {
    const error = new BaseError()

    expect(error.errorType).toBe('BaseError')
    expect(error.message).toBe('')
    expect(error.errorCode).toBe(undefined)
    expect(error.stack).toBeDefined()
  })

  it('should accept error message', () => {
    const error = new BaseError('Something bad happened.')

    expect(error.errorType).toBe('BaseError')
    expect(error.message).toBe('Something bad happened.')
    expect(error.errorCode).toBe(undefined)
    expect(error.stack).toBeDefined()
  })

  it('should accept error code', () => {
    const error = new BaseError('Something else bad happened.', 21)

    expect(error.errorType).toBe('BaseError')
    expect(error.message).toBe('Something else bad happened.')
    expect(error.errorCode).toBe(21)
    expect(error.stack).toBeDefined()
  })

  it('should accept error instance', () => {
    const genericError = new Error('Something unexpected happened.')
    const error = new BaseError(genericError)

    expect(error.errorType).toBe('BaseError')
    expect(error.message).toBe('Something unexpected happened.')
    expect(error.errorCode).toBe(undefined)
    expect(error.stack).toBe(genericError.stack)
  })

  it('should save error type with generic error', () => {
    const genericError = new Error('Something unexpected happened.')
    const error = new BaseError(genericError, 12)

    expect(error.errorType).toBe('BaseError')
    expect(error.message).toBe('Something unexpected happened.')
    expect(error.errorCode).toBe(12)
    expect(error.stack).toBe(genericError.stack)

    expect(error.originalErrorType).toBe('[[no-type]:[no-code]]')
  })

  it('should save error type with non-generic error', () => {
    const otherError = new BaseError('Something unexpected happened.', 56)
    const error = new BaseError(otherError, 12)

    expect(error.errorType).toBe('BaseError')
    expect(error.message).toBe('Something unexpected happened.')
    expect(error.errorCode).toBe(12)
    expect(error.stack).toBe(otherError.stack)

    expect(error.originalErrorType).toBe('[BaseError:56]')
  })
})
