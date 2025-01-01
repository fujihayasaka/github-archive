import type {JSONRequestInit} from '@github-ui/verified-fetch'
import {reactFetchJSON} from '@github-ui/verified-fetch'

/**
 *
 * Use when catching a "TypeError: Failed to fetch" error.
 * Typically happens when the fetch request catches one of the following:
 * - CORS
 * - Browser Extensions are calling or modifying the response
 * - Incorrect or Incomplete URL
 * - Incorrect or Incomplete Headers, URL or HTTP Methods
 * - Or when the request is blocked by the browser's Content Security Policy (CSP)
 */
export class FetchRequestError extends Error {
  constructor(cause: unknown) {
    super('Unable to perform this operation. Please try again later.')
    this.name = 'FetchRequestError'
    this.cause = cause
  }
}

/**
 *
 * Use when server returns a 500 error (e.g. server is unavailable)
 */
export class ServerUnavailableError extends Error {
  constructor(cause: unknown) {
    super('Unable to perform this operation. Please try again later.')
    this.name = 'ServerUnavailableError'
    this.cause = cause
  }
}

/**
 *
 * Use when server returns invalid json.
 * e.g.
 * - JSON.parse: unexpected character at line 1 column 1 of the JSON data
 * - <HTML> or <DOCTYPE> is returned
 */
export class JSONParseFetchError extends Error {
  constructor(cause: unknown) {
    super('Unable to read response from the server. Please try again later.')
    this.name = 'JSONParseFetchError'
    this.cause = cause
  }
}

// Used when a user's SSO session expires and we fail to return the previous data.
export class AuthSessionExpiredError extends Error {
  constructor() {
    super('Unable to perform this operation. Please try again later.')
    this.name = 'AuthSessionExpiredError'
  }
}

/**
 *
 * @param response Response
 * @returns Promise<any>
 * @throws {JSONParseFetchError} if it's unable to parse JSON from the response
 *
 * Use to wrap JSON parsing from HTTP response with better error messages.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function parseJSONWithBetterErrors(response: Response): Promise<any> {
  // Attempt to parse JSON, but if it fails, throw a generic error
  try {
    return await response.json()
  } catch (e) {
    throw new JSONParseFetchError(e)
  }
}

/**
 *
 * @param response Response
 * @param json object
 * @param predefinedError Error
 * @returns void
 * @throws {ServerUnavailableError} if response has a 5xx status.
 * @throws {predefinedError} if provided and response status is not a 5xx.
 * @throw {Error} using json values if json is passed without predefinedError or response is not a 5xx status.
 * @throw Error with response.status if none of the above.
 */
export function throwErrorsIfBadResponse(response: Response, json?: {error?: string}, predefinedError?: Error): void {
  if (response.ok) return

  if (response.status >= 500) {
    throw new ServerUnavailableError(response.status)
  }

  if (predefinedError) {
    throw predefinedError
  }

  if (json) {
    throw new Error(json?.error || 'Unknown error occurred', {cause: response.status})
  }

  throw new Error(`HTTP ${response.status}`)
}

/**
 *
 * @param path string
 * @param init JSONRequestInit
 * @returns Response
 *
 * Use when you want to make a fetch request.
 * This function wraps reactFetchJSON and handles unsafe fetching
 */
export async function fetchWithErrorHandling(path: string, init?: JSONRequestInit): Promise<Response> {
  try {
    return await reactFetchJSON(path, init)
  } catch (e) {
    throw new FetchRequestError(e)
  }
}
