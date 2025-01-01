import type {AuthTokenResult, SerializedAuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {AuthToken} from '@github-ui/copilot-auth-token/auth-token'

export class SparkAuthToken extends AuthToken {
  /**
   * Returns true if this auth token is expired.
   */
  override get isExpired() {
    const expirationDateString = new Date(this.expiration)

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

    const padding = 1000 * 60 * 15 // 15 minutes in ms

    return expirationDate < new Date(Date.now() + padding)
  }

  /**
   * Build a new AuthToken from the results of a call to the token API endpoint.
   */
  static override fromResult(result: AuthTokenResult, orgIds: string[]) {
    return new SparkAuthToken(result.token, result.expiration, orgIds)
  }

  /**
   * Build a new auth token from a plain JS object, i.e. one parsed from localStorage.
   */
  static override deserialize(serialized: SerializedAuthToken): SparkAuthToken {
    return new SparkAuthToken(serialized.value, serialized.expiration, serialized.ssoOrgIDs)
  }
}
