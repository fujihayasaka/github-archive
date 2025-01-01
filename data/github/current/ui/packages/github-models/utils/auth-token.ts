import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {AuthTokenResult} from '../types'

export const authTokenUrl = '/marketplace/models/token'

/**
 * AuthToken represents an authentication token that is passed to azure.ai, which is used to authenticate
 * requests to the Azure AI API.
 *
 * It also can tell if it needs refreshing, i.e. if it is expired or if the SSO orgs have changed since
 * it was minted.
 *
 * Finally, it can convert itself to/from ordinary JS objects that can be stored/retrieved from
 * local storage.
 */
export class AuthToken {
  token: string | undefined
  expiration: string | undefined
  currentAuthTokenRequest: Promise<AuthToken> | null
  authTokenLocalStorageKey: string = 'NEUTRON_AUTH_TOKEN'
  authTokenLocalStorageOverwriteKey: string = 'NEUTRON_AUTH_TOKEN_OVERWRITE'

  constructor(token?: string, expiration?: string) {
    this.token = token
    this.expiration = expiration
    this.currentAuthTokenRequest = null
  }

  /**
   * Returns a formatted string to be used as the value of an `Authorization` header,
   * e.g. "GitHub-Bearer <encrypted token>"
   */
  get authorizationHeaderValue() {
    return `GitHub-Bearer ${this.token}`
  }

  /**
   * Returns true if this auth token needs to be refreshed.
   */
  needsRefreshing() {
    return this.isExpired
  }

  /**
   * Returns true if this auth token is expired.
   */
  get isExpired() {
    const expirationDateString = new Date(this.expiration || new Date(0).toISOString())

    const expirationDate = new Date(
      Date.UTC(
        expirationDateString.getUTCFullYear(),
        expirationDateString.getUTCMonth(),
        expirationDateString.getUTCDate(),
        expirationDateString.getUTCHours(),
        expirationDateString.getUTCMinutes(),
        expirationDateString.getUTCSeconds(),
        expirationDateString.getUTCMilliseconds(),
      ),
    )

    const padding = 15 * 1000 // seconds

    return expirationDate < new Date(Date.now() + padding)
  }

  /**
   * Build a new AuthToken from the results of a call to the token API endpoint.
   */
  static fromResult(result: AuthTokenResult) {
    return new AuthToken(result.token, result.expiration)
  }

  /**
   * Convert this token into a plain JS object, which can be stringified and put into localStorage.
   */
  serialize(): AuthTokenResult {
    return {
      token: this.token,
      expiration: this.expiration,
    }
  }

  /**
   * Build a new auth token from a plain JS object, i.e. one parsed from localStorage.
   */
  static deserialize(serialized: AuthTokenResult): AuthToken {
    return new AuthToken(serialized.token, serialized.expiration)
  }

  async getAuthTokenValue(): Promise<string> {
    // For local dev, set local storage with key this.authTokenLocalStorageOverwriteKey to "Bearer <PAT>"
    const tokenOverwrite = localStorage.getItem(this.authTokenLocalStorageOverwriteKey)
    return tokenOverwrite ?? (await this.getAuthToken()).authorizationHeaderValue
  }

  /**
   * Get the current auth token, either from local storage or by minting a new one from dotcom.
   */
  async getAuthToken(): Promise<AuthToken> {
    // For local dev, set local storage with key this.authTokenLocalStorageOverwriteKey to "Bearer <PAT>"
    const tokenOverwrite = localStorage.getItem(this.authTokenLocalStorageOverwriteKey)
    if (tokenOverwrite) {
      return new AuthToken(tokenOverwrite.replace('Bearer ', ''))
    }

    const stored = localStorage.getItem(this.authTokenLocalStorageKey)

    if (!stored) {
      return this.fetchAuthToken()
    }
    const token = AuthToken.deserialize(JSON.parse(stored) as AuthTokenResult)
    return this.validateAuthToken(token)
  }

  /**
   * Validate the given auth token.  If it's all good, return it, otherwise, go mint a new one from
   * dotcom and return it instead.
   */
  private async validateAuthToken(token: AuthToken): Promise<AuthToken> {
    return token.needsRefreshing() ? this.fetchAuthToken() : token
  }

  /**
   * Return the current auth token request, or start a new one.
   *
   * The inner workings of the chat app can cause multiple requests to CAPI in quick succession.  If we
   * do not have an auth token available in local storage, each of those requests will trigger their own
   * token fetch, hence the storing of the current request on `this`.
   */
  private fetchAuthToken(): Promise<AuthToken> {
    if (!this.currentAuthTokenRequest) {
      this.currentAuthTokenRequest = this._fetchAuthToken()
    }

    return this.currentAuthTokenRequest
  }

  /**
   * Start a new auth token request, parsing the result, persisting it in local storage,
   * and clearing the current request once finished.
   */
  private async _fetchAuthToken(): Promise<AuthToken> {
    const response = await verifiedFetchJSON(authTokenUrl, {method: 'POST'})

    if (response.ok) {
      const result = (await response.json()) as AuthTokenResult

      this.currentAuthTokenRequest = null

      const token = AuthToken.fromResult(result)

      localStorage.setItem(this.authTokenLocalStorageKey, JSON.stringify(token.serialize()))

      return token
    } else {
      this.currentAuthTokenRequest = null

      const result = await response.json()
      if (result.error) {
        throw new Error(result.error)
      } else {
        throw new Error('Failed to mint new auth token')
      }
    }
  }
}

const instance = new AuthToken()

export default instance
