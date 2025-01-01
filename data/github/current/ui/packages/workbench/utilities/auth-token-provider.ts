import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import type {AuthTokenResult, SerializedAuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import {SparkAuthToken} from './auth-token'

export const AUTH_TOKEN_ENDPOINT = '/spark/runtime/token'
export const AUTH_TOKEN_STORAGE_KEY = 'SPARK_AUTH_TOKEN'

export class SparkAuthTokenProvider extends CopilotAuthTokenProvider {
  constructor(ssoOrgIDs: string[]) {
    super(ssoOrgIDs, AUTH_TOKEN_ENDPOINT, AUTH_TOKEN_STORAGE_KEY)
  }

  override getLocalStorageAuthToken(): SparkAuthToken | null {
    const value = this.copilotLocalStorage.getItem(this.storageKey)

    return value ? SparkAuthToken.deserialize(JSON.parse(value) as SerializedAuthToken) : null
  }

  /**
   * Start a new auth token request, parsing the result, persisting it in local storage,
   * and clearing the current request once finished.
   */
  protected override async _fetchAuthToken(): Promise<SparkAuthToken> {
    const response = await verifiedFetchJSON(this.tokenEndpoint, {method: 'POST'})

    if (response.ok) {
      const result = (await response.json()) as AuthTokenResult
      this.currentAuthTokenRequest = null

      const token = SparkAuthToken.fromResult(result, this.ssoOrgIDs)

      this.setLocalStorageAuthToken(token)

      return token
    } else {
      this.currentAuthTokenRequest = null

      throw new Error('Failed to mint new auth token')
    }
  }
}
