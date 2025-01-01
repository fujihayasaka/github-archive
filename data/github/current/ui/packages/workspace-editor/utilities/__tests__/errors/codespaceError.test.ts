import {BaseError, CodespaceError} from '../../../errors'
import {CodespaceStateInfo} from '../../workspace-editor-types'

describe('CodespaceError', () => {
  it('should extend BaseError and have the correct error type', () => {
    const error = new CodespaceError('Failed to create codespace.')

    expect(error).toBeInstanceOf(BaseError)
    expect(error).toBeInstanceOf(Error)
    expect(error.errorType).toBe('CodespaceError')
    expect(error.message).toBe('Failed to create codespace.')
    expect(error.codespaceState).toBe(undefined)
    expect(error.stack).toBeDefined()
  })

  it('should accept error code', () => {
    const error = new CodespaceError('Something else bad happened.')

    expect(error.errorType).toBe('CodespaceError')
    expect(error.message).toBe('Something else bad happened.')
    expect(error.errorCode).toBe(undefined)
    expect(error.stack).toBeDefined()
  })

  it('should accept generic error instance', () => {
    const genericError = new Error('Something unexpected happened.')
    const error = new CodespaceError(genericError)

    expect(error.errorType).toBe('CodespaceError')
    expect(error.message).toBe('Something unexpected happened.')
    expect(error.errorCode).toBe(undefined)
    expect(error.stack).toBe(genericError.stack)
  })

  it('should accept non-generic error instance', () => {
    const genericError = new BaseError('Something unexpected happened.', 21)
    const error = new CodespaceError(genericError)

    expect(error.errorType).toBe('CodespaceError')
    expect(error.message).toBe('Something unexpected happened.')
    expect(error.errorCode).toBe(21)
    expect(error.stack).toBe(genericError.stack)
  })

  describe('accepts Codespace state', () => {
    it('should accept `failed` Codespace state', () => {
      const error = new CodespaceError('Codespace is in a bad state.', CodespaceStateInfo.Failed)

      expect(error.message).toBe('Codespace is in a bad state.')
      expect(error.codespaceState).toBe(CodespaceStateInfo.Failed)

      expect(error).toBeInstanceOf(BaseError)
      expect(error).toBeInstanceOf(Error)
      expect(error.errorType).toBe('CodespaceError')
      expect(error.stack).toBeDefined()
    })

    it('should accept `unavailable` Codespace state', () => {
      const error = new CodespaceError('Codespace is in a bad state.', CodespaceStateInfo.Unavailable)

      expect(error.message).toBe('Codespace is in a bad state.')
      expect(error.codespaceState).toBe(CodespaceStateInfo.Unavailable)

      expect(error).toBeInstanceOf(BaseError)
      expect(error).toBeInstanceOf(Error)
      expect(error.errorType).toBe('CodespaceError')
      expect(error.stack).toBeDefined()
    })
  })
})
