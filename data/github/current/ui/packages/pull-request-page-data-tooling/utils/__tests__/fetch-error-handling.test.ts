// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'

import {
  FetchRequestError,
  fetchWithErrorHandling,
  JSONParseFetchError,
  parseJSONWithBetterErrors,
  ServerUnavailableError,
  throwErrorsIfBadResponse,
} from '../fetch-error-handling'

let globalFetch = global.fetch

beforeEach(() => {
  globalFetch = global.fetch
})

afterEach(() => {
  global.fetch = globalFetch
})

describe('parseJSONWithBetterErrors', () => {
  test('throws a JSONParseFetchError when the response has invalid JSON', async () => {
    const response = new Response('invalid json', {status: 200})
    let thrownError: JSONParseFetchError | null = null
    try {
      await parseJSONWithBetterErrors(response)
    } catch (error) {
      thrownError = error as JSONParseFetchError
    }

    expect(thrownError).toBeInstanceOf(JSONParseFetchError)
    expect(thrownError?.message).toBe('Unable to read response from the server. Please try again later.')
  })

  test('does not throw a JSONParseFetchError when the response is valid JSON', async () => {
    const response = new Response('{}', {status: 200})
    let thrownError: JSONParseFetchError | null = null
    try {
      await parseJSONWithBetterErrors(response)
    } catch (error) {
      thrownError = error as JSONParseFetchError
    }

    expect(thrownError).toBeNull()
  })
})

describe('throwErrorsIfBadResponse', () => {
  test('throws a ServerUnavailableError when the response has a 5xx status', () => {
    for (let status = 500; status <= 511; status++) {
      const response = new Response('', {status})
      let thrownError: JSONParseFetchError | null = null
      try {
        throwErrorsIfBadResponse(response)
      } catch (error) {
        thrownError = error as ServerUnavailableError
      }

      expect(thrownError).toBeInstanceOf(ServerUnavailableError)
      expect(thrownError?.message).toBe('Unable to perform this operation. Please try again later.')
      expect(thrownError?.cause).toBe(status)
    }
  })

  test('throws a predefinedError when the response does not have a 5xx and predefinedError is provided', () => {
    const response = new Response('', {status: 400})
    class PredefinedError extends Error {
      constructor() {
        super('Predefined Error')
        this.name = 'PredefinedError'
      }
    }
    const predefinedError = new PredefinedError()
    let thrownError: PredefinedError | null = null

    try {
      throwErrorsIfBadResponse(response, {}, predefinedError)
    } catch (error) {
      thrownError = error as PredefinedError
    }

    expect(thrownError).toBeInstanceOf(PredefinedError)
    expect(thrownError?.message).toBe(predefinedError.message)
    expect(thrownError?.name).toBe(predefinedError.name)
  })

  test('throws an Error with the response status when the response does not have a 5xx and no predefinedError is provided', () => {
    const response = new Response('', {status: 400})
    let thrownError: Error | null = null

    try {
      throwErrorsIfBadResponse(response)
    } catch (error) {
      thrownError = error as Error
    }

    expect(thrownError).toBeInstanceOf(Error)
    expect(thrownError?.message).toBe('HTTP 400')
  })

  test('throws an Error with the response status when the response does not have a 5xx and no predefinedError is provided, but JSON is provided with error field', () => {
    const response = new Response('', {status: 400})
    let thrownError: Error | null = null

    try {
      throwErrorsIfBadResponse(response, {error: 'Random error message'})
    } catch (error) {
      thrownError = error as Error
    }

    expect(thrownError).toBeInstanceOf(Error)
    expect(thrownError?.message).toBe('Random error message')
    expect(thrownError?.cause).toBe(400)
  })

  test('throws an Error with the response status when the response does not have a 5xx and no predefinedError is provided, but JSON is provided without an error field', () => {
    const response = new Response('', {status: 400})
    let thrownError: Error | null = null

    try {
      throwErrorsIfBadResponse(response, {})
    } catch (error) {
      thrownError = error as Error
    }

    expect(thrownError).toBeInstanceOf(Error)
    expect(thrownError?.message).toBe('Unknown error occurred')
    expect(thrownError?.cause).toBe(400)
  })

  test('does not throw an error when the response is "ok"', () => {
    const response = new Response('', {status: 200})
    let thrownError: Error | null = null

    try {
      throwErrorsIfBadResponse(response)
    } catch (error) {
      thrownError = error as Error
    }

    expect(thrownError).toBeNull()
  })
})

describe('fetchWithErrorHandling', () => {
  test('throws a FetchRequestError when fetch fails', async () => {
    global.fetch = jest.fn(() => Promise.reject(new TypeError('Failed to fetch'))) as jest.Mock

    let thrownError: FetchRequestError | null = null
    try {
      await fetchWithErrorHandling('https://example.com')
    } catch (error) {
      thrownError = error as FetchRequestError
    }

    expect(thrownError).toBeInstanceOf(FetchRequestError)
    expect(thrownError?.message).toBe('Unable to perform this operation. Please try again later.')
  })

  test('does not throw a FetchRequestError when fetch resolves correctly', async () => {
    mockFetch.mockRoute('/example-route', {})
    let thrownError: FetchRequestError | null = null
    try {
      await fetchWithErrorHandling('/example-route')
    } catch (error) {
      thrownError = error as FetchRequestError
    }

    expect(thrownError).toBeNull()
  })
})
