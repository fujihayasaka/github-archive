// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {BaseError, HttpError} from '../../../errors'

describe('HttpError', () => {
  it('should extend BaseError and have the correct error type', () => {
    const error = new HttpError(402, 'Payment required.')

    expect(error).toBeInstanceOf(BaseError)
    expect(error).toBeInstanceOf(Error)
    expect(error.errorType).toBe('HttpError')

    expect(error.status).toBe(402)
    expect(error.statusText).toBe('Payment required.')
  })

  it('should create correct error message if no additional message is provided', () => {
    const error = new HttpError(403, 'Forbidden.')

    expect(error.status).toBe(403)
    expect(error.statusText).toBe('Forbidden.')
    expect(error.message).toBe('HTTP request failed: 403 - Forbidden.')
  })

  it('should create correct error message if additional message is provided', () => {
    const error = new HttpError(404, 'Not found.', 'Failed to fetch data')

    expect(error.status).toBe(404)
    expect(error.statusText).toBe('Not found.')
    expect(error.message).toBe('Failed to fetch data: 404 - Not found.')
  })

  describe('fromResponse', () => {
    it('should be able to initialize from a Response instance', () => {
      const response = {
        status: 404,
        statusText: 'Not found.',
      } as Response
      const error = HttpError.fromResponse(response, 'Something failed')

      expect(error.status).toBe(404)
      expect(error.statusText).toBe('Not found.')
      expect(error.message).toBe('Something failed: 404 - Not found.')
      expect(error.isRetriable()).toBe(false)
    })
  })

  describe('isRetriable', () => {
    it('should return `false` for non-retriable statuses', () => {
      for (const code of [400, 401, 403, 404]) {
        const error = new HttpError(code, `(${code}) Some status text.`)

        expect(error.status).toBe(code)
        expect(error.statusText).toBe(`(${code}) Some status text.`)
        expect(error.isRetriable()).toBe(false)
      }
    })

    it('should return `true` for all other statuses', () => {
      for (const code of [402, 500, 501, 502]) {
        const error = new HttpError(code, `(${code}) Some status text.`)

        expect(error.status).toBe(code)
        expect(error.statusText).toBe(`(${code}) Some status text.`)
        expect(error.isRetriable()).toBe(true)
      }
    })
  })
})
