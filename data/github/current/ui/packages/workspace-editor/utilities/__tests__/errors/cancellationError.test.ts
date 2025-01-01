import {BaseError, CancellationError} from '../../../errors'

describe('CancellationError', () => {
  it('should extend BaseError', () => {
    const error = new CancellationError()

    expect(error).toBeInstanceOf(BaseError)
    expect(error).toBeInstanceOf(Error)
  })

  it('should have correct error type', () => {
    const error = new CancellationError()

    expect(error.errorType).toBe('CancellationError')
  })

  it('should accept error message', () => {
    const error = new CancellationError('Something bad happened.')

    expect(error.errorType).toBe('CancellationError')
    expect(error.message).toBe('Something bad happened.')
    expect(error.errorCode).toBe(undefined)
    expect(error.stack).toBeDefined()
  })

  it('should accept error code', () => {
    const error = new CancellationError('Something else bad happened.', 21)

    expect(error.errorType).toBe('CancellationError')
    expect(error.message).toBe('Something else bad happened.')
    expect(error.errorCode).toBe(21)
    expect(error.stack).toBeDefined()
  })

  it('should accept error instance', () => {
    const genericError = new Error('Something unexpected happened.')
    const error = new CancellationError(genericError)

    expect(error.errorType).toBe('CancellationError')
    expect(error.message).toBe('Something unexpected happened.')
    expect(error.errorCode).toBe(undefined)
    expect(error.stack).toBe(genericError.stack)
  })
})
