import {AuthToken, type AuthTokenResult, type SerializedAuthToken} from './auth-token'
import safeStorage from '@github-ui/safe-storage'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

export const COPILOT_AUTH_TOKEN_KEY = 'COPILOT_AUTH_TOKEN'

export class CopilotAuthTokenProvider {
  protected readonly tokenEndpoint: string
  protected readonly storageKey: string
  ssoOrgIDs: string[]
  currentAuthTokenRequest: Promise<AuthToken> | null
  copilotLocalStorage: {
    getItem: (key: string, now?: number) => string | null
    setItem: (key: string, value: string, now?: number) => void
  }

  constructor(
    ssoOrgIDs: string[],
    tokenEndpoint: string = '/github-copilot/chat/token',
    storageKey: string = COPILOT_AUTH_TOKEN_KEY,
  ) {
    this.ssoOrgIDs = ssoOrgIDs
    this.currentAuthTokenRequest = null
    this.copilotLocalStorage = safeStorage('localStorage', {
      throwQuotaErrorsOnSet: false,
      ttl: 1000 * 60 * 60 * 24,
    })
    this.storageKey = storageKey
    this.tokenEndpoint = tokenEndpoint
  }

  /**
   * Get the current auth token, either from local storage or by minting a new one from dotcom.
   */
  async getAuthToken(): Promise<AuthToken> {
    const token = this.getLocalStorageAuthToken()

    return token ? this.validateAuthToken(token) : this.fetchAuthToken()
  }

  setLocalStorageAuthToken(token: AuthToken) {
    this.copilotLocalStorage.setItem(this.storageKey, JSON.stringify(token.serialize()))
  }

  getLocalStorageAuthToken(): AuthToken | null {
    const value = this.copilotLocalStorage.getItem(this.storageKey)

    return value ? AuthToken.deserialize(JSON.parse(value) as SerializedAuthToken) : null
  }

  /**
   * Temporarily used to support Spark App use case while we wait to get our own Global GH App and
   * token management setup. If the token will exipire in the next 7 minutes, we will fetch a new one.
   * Sparks reuse that token for all requests made by the agent in an iteration, which can run ~5 minutes
   * long.
   *
   * Remove when the spark_auth_token_endpoint FF is removed.
   */
  async getTokenForSpark(): Promise<AuthToken> {
    const token = await this.getAuthToken()
    const expirationDateString = new Date(token.expiration)
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
    const padding = 7 * 60000 // 7 minutes

    if (expirationDate < new Date(Date.now() + padding)) {
      return this.fetchAuthToken()
    } else {
      return token
    }
  }

  /**
   * Validate the given auth token.  If it's all good, return it, otherwise, go mint a new one from
   * dotcom and return it instead.
   */
  private async validateAuthToken(token: AuthToken): Promise<AuthToken> {
    return token.needsRefreshing(this.ssoOrgIDs) ? this.fetchAuthToken() : token
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
  protected async _fetchAuthToken(): Promise<AuthToken> {
    const response = await verifiedFetchJSON(this.tokenEndpoint, {method: 'POST'})

    if (response.ok) {
      const result = (await response.json()) as AuthTokenResult
      this.currentAuthTokenRequest = null

      const token = AuthToken.fromResult(result, this.ssoOrgIDs)

      this.setLocalStorageAuthToken(token)

      return token
    } else {
      this.currentAuthTokenRequest = null

      throw new Error('Failed to mint new auth token')
    }
  }
}
