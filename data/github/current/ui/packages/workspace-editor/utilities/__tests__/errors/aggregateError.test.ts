// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {AggregateError, AssertionError, BaseError, CancellationError, CodespaceError, HttpError} from '../../../errors'
import {assertDefined} from '../../asserts'
import {CodespaceStateInfo} from '../../workspace-editor-types'

describe('AggregateError', () => {
  it('should extend BaseError and have the correct error type', () => {
    const error = new AggregateError('Failed to create codespace.')

    expect(error).toBeInstanceOf(BaseError)
    expect(error).toBeInstanceOf(Error)
    expect(error.errorType).toBe('AggregateError')
    expect(error.message).toBe('Failed to create codespace.')
    expect(error.stack).toBeDefined()

    expect(error.errors.length).toBe(0)
    expect(error.lastError).toBe(undefined)
  })

  describe('errors list', () => {
    it('should contain list of some errors', () => {
      const error = new AggregateError('Ooops.')

      for (let i = 0; i < 5; i++) {
        error.addErrors(new Error(`Error ${i}.`))
      }

      expect(error.errors.length).toBe(5)
      for (let i = 0; i < 5; i++) {
        const currentError = error.errors[i]
        assertDefined(currentError, `Error ${i} must be defined.`)
        expect(currentError.message).toBe(`Error ${i}.`)
        expect(currentError).toBeInstanceOf(Error)
      }

      expect(error.errorType).toBe('AggregateError')
      expect(error.message).toBe('Ooops. Error 4.')
      expect(error.stack).toBeDefined()
    })

    it('should be able to receive N errors at once', () => {
      const error = new AggregateError('Some other ooops.')

      // add a bunch of different errors at once
      error.addErrors(
        new Error('Generic error 1.'),
        new BaseError('Base error 2.'),
        new CancellationError('Cancellation error 3.'),
        new AssertionError('Assertion error 4.'),
        new HttpError(401, 'Http error 5.'),
        new CodespaceError(new Error('Codespace error 6.'), CodespaceStateInfo.Unavailable),
        new AggregateError('Aggregate error 7.'),
      )

      expect(error.errors.length).toBe(7)
      expect(error.errorType).toBe('AggregateError')
      expect(error.message).toBe('Some other ooops. Aggregate error 7.')
      expect(error.stack).toBeDefined()

      expect(error.errors[0]).toBeInstanceOf(Error)
      expect(error.errors[0]?.message).toBe('Generic error 1.')

      expect(error.errors[1]).toBeInstanceOf(BaseError)
      expect(error.errors[1]?.message).toBe('Base error 2.')

      expect(error.errors[2]).toBeInstanceOf(CancellationError)
      expect(error.errors[2]?.message).toBe('Cancellation error 3.')

      expect(error.errors[3]).toBeInstanceOf(AssertionError)
      expect(error.errors[3]?.message).toBe('Assertion error 4.')

      expect(error.errors[4]).toBeInstanceOf(HttpError)
      expect(error.errors[4]?.message).toBe('HTTP request failed: 401 - Http error 5.')

      expect(error.errors[5]).toBeInstanceOf(CodespaceError)
      expect(error.errors[5]?.message).toBe('Codespace error 6.')

      expect(error.errors[6]).toBeInstanceOf(AggregateError)
      expect(error.errors[6]?.message).toBe('Aggregate error 7.')

      expect(error.errors[7]).not.toBeDefined()
    })

    it('should return the last error in the list', () => {
      const error = new AggregateError()

      // add a bunch of different errors at once
      error.addErrors(
        new BaseError('Base error.'),
        new AggregateError('Aggregate error.'),
        new CancellationError('Cancellation error.'),
      )

      expect(error.errors.length).toBe(3)
      expect(error.lastError).toBeInstanceOf(CancellationError)

      error.addErrors(
        new AssertionError('Assertion error.'),
        new Error('Generic error.'),
        new CodespaceError(new Error('Codespace error.'), CodespaceStateInfo.Unavailable),
        new HttpError(401, 'Http error.'),
      )

      expect(error.errors.length).toBe(7)
      expect(error.lastError).toBeInstanceOf(HttpError)
    })
  })

  describe('error message', () => {
    it('should return message of the last error in the list', () => {
      const error = new AggregateError()

      // add a bunch of different errors at once
      error.addErrors(
        new BaseError('Base error.'),
        new AggregateError('Aggregate error.'),
        new CancellationError('Cancellation error.'),
      )

      expect(error.errors.length).toBe(3)
      expect(error.lastError).toBeInstanceOf(CancellationError)
      expect(error.message).toBe('Cancellation error.')

      error.addErrors(
        new AssertionError('Assertion error.'),
        new Error('Generic error.'),
        new CodespaceError(new Error('Codespace error.'), CodespaceStateInfo.Unavailable),
        new HttpError(401, 'Some HTTP failure.'),
      )

      expect(error.errors.length).toBe(7)
      expect(error.lastError).toBeInstanceOf(HttpError)
      expect(error.message).toBe('HTTP request failed: 401 - Some HTTP failure.')
    })

    it('should return its own message, if defined', () => {
      const error = new AggregateError('Oh no! ><')

      // add a bunch of different errors at once
      error.addErrors(
        new BaseError('Base error.'),
        new CancellationError('Cancellation error.'),
        new AggregateError('Aggregate error 15.'),
      )

      expect(error.errors.length).toBe(3)
      expect(error.lastError).toBeInstanceOf(AggregateError)
      expect(error.message).toBe('Oh no! >< Aggregate error 15.')

      error.addErrors(
        new HttpError(401, 'Some HTTP failure.'),
        new CodespaceError(new Error('Codespace error.'), CodespaceStateInfo.Unavailable),
        new Error('Generic error.'),
        new AssertionError('Assertion error 12.'),
      )

      expect(error.errors.length).toBe(7)
      expect(error.lastError).toBeInstanceOf(AssertionError)
      expect(error.message).toBe('Oh no! >< Assertion error 12.')
    })
  })

  describe('cloneWithErrors', () => {
    it('should clone aggregate error instance with all underlying errors', () => {
      const error = new AggregateError('Not again!', 17)

      // add a bunch of different errors at once
      error.addErrors(
        new CodespaceError(new Error('Codespace error 6.'), CodespaceStateInfo.Unavailable),
        new AggregateError('Aggregate error 7.'),
        new AssertionError('Assertion error 4.'),
        new HttpError(401, 'Http error 5.'),
        new Error('Generic error 1.'),
        new BaseError('Base error 2.'),
        new AssertionError('Assertion error 8.'),
        new CancellationError('Cancellation error 3.'),
      )

      expect(error.errors.length).toBe(8)
      expect(error.lastError).toBeInstanceOf(CancellationError)

      // clone and add more errors
      const errorClone = error.cloneWithErrors(
        new AggregateError('Aggregate error 9.'),
        new AssertionError('Assertion error 10.'),
      )

      expect(errorClone.errors.length).toBe(10)
      expect(errorClone.lastError).toBeInstanceOf(AssertionError)
      expect(errorClone.lastError?.message).toBe('Assertion error 10.')

      expect(errorClone).toBeInstanceOf(AggregateError)
      expect(errorClone.errorType).toBe('AggregateError')
      expect(errorClone.errorCode).toBe(17)
      expect(errorClone.message).toBe('Not again! Assertion error 10.')

      // validate that the errors order is preserved
      expect(errorClone.errors[0]).toBeInstanceOf(CodespaceError)
      expect(errorClone.errors[1]).toBeInstanceOf(AggregateError)
      expect(errorClone.errors[2]).toBeInstanceOf(AssertionError)
      expect(errorClone.errors[3]).toBeInstanceOf(HttpError)
      expect(errorClone.errors[4]).toBeInstanceOf(Error)
      expect(errorClone.errors[5]).toBeInstanceOf(BaseError)
      expect(errorClone.errors[6]).toBeInstanceOf(AssertionError)
      expect(errorClone.errors[7]).toBeInstanceOf(CancellationError)
      expect(errorClone.errors[8]).toBeInstanceOf(AggregateError)
      expect(errorClone.errors[9]).toBeInstanceOf(AssertionError)
    })

    it('should clone aggregate error instance with all underlying errors (no won error message)', () => {
      const error = new AggregateError()

      // add a bunch of different errors at once
      error.addErrors(
        new CodespaceError(new Error('Codespace error 6.'), CodespaceStateInfo.Unavailable),
        new AggregateError('Aggregate error 7.'),
        new AssertionError('Assertion error 4.'),
        new HttpError(401, 'Http error 5.'),
        new Error('Generic error 1.'),
        new BaseError('Base error 2.'),
        new AssertionError('Assertion error 8.'),
        new CancellationError('Cancellation error 3.'),
      )

      expect(error.errors.length).toBe(8)
      expect(error.lastError).toBeInstanceOf(CancellationError)

      // clone and add more errors
      const errorClone = error.cloneWithErrors(
        new AggregateError('Aggregate error 9.'),
        new AssertionError('Assertion error 10.'),
      )

      expect(errorClone).toBeInstanceOf(AggregateError)
      expect(errorClone.errors.length).toBe(10)
      expect(errorClone.lastError).toBeInstanceOf(AssertionError)
      expect(errorClone.errorType).toBe('AggregateError')
      expect(errorClone.message).toBe(errorClone.lastError?.message)

      // validate that the errors order is preserved
      expect(errorClone.errors[0]).toBeInstanceOf(CodespaceError)
      expect(errorClone.errors[1]).toBeInstanceOf(AggregateError)
      expect(errorClone.errors[2]).toBeInstanceOf(AssertionError)
      expect(errorClone.errors[3]).toBeInstanceOf(HttpError)
      expect(errorClone.errors[4]).toBeInstanceOf(Error)
      expect(errorClone.errors[5]).toBeInstanceOf(BaseError)
      expect(errorClone.errors[6]).toBeInstanceOf(AssertionError)
      expect(errorClone.errors[7]).toBeInstanceOf(CancellationError)
      expect(errorClone.errors[8]).toBeInstanceOf(AggregateError)
      expect(errorClone.errors[9]).toBeInstanceOf(AssertionError)
    })
  })

  describe('throw', () => {
    it('should throw the last error', () => {
      const error = new AggregateError('Ooops.')

      // add a bunch of different errors at once
      error.addErrors(
        new CodespaceError(new Error('Codespace error 6.'), CodespaceStateInfo.Unavailable),
        new AggregateError('Aggregate error 7.'),
        new AssertionError('Assertion error 4.'),
        new HttpError(401, 'Http error 5.'),
        new Error('Generic error 1.'),
        new BaseError('Base error 2.'),
        new AssertionError('Assertion error 8.'),
        new CancellationError('Cancellation error 32.'),
      )

      expect(() => {
        error.throw(true)
      }).toThrowErrorMatchingSnapshot()
    })

    it('should throw itself', () => {
      const error = new AggregateError('Uggh ohh!')

      // add a bunch of different errors at once
      error.addErrors(
        new AggregateError('Aggregate error 7.'),
        new AssertionError('Assertion error 4.'),
        new HttpError(401, 'Http error 5.'),
        new BaseError('Base error 2.'),
        new CancellationError('Cancellation error 32.'),
        new AssertionError('Assertion error 8.'),
        new Error('Generic error 1.'),
        new CodespaceError(new Error('Codespace error 6.'), CodespaceStateInfo.Unavailable),
      )

      expect(() => {
        error.throw(false)
      }).toThrowErrorMatchingSnapshot()
    })

    it('should throw itself if no underlying errors present', () => {
      const error = new AggregateError('Uggh ohh noes!')

      expect(() => {
        error.throw(true)
      }).toThrowErrorMatchingSnapshot()
    })
  })
})
