import defaultAuthToken, {AuthToken, authTokenUrl} from '../auth-token'
import type {AuthTokenResult} from '../../types'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
}))

describe('AuthToken', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  describe('authorizationHeaderValue', () => {
    test('returns string for use in Authorization header', () => {
      const token = 'HelloNiceToken'
      const authToken = new AuthToken(token)
      expect(authToken.authorizationHeaderValue).toBe(`GitHub-Bearer ${token}`)
    })
  })

  describe('needsRefreshing', () => {
    test('returns true if token is expired', () => {
      const expiration = new Date(Date.now() - 1000).toISOString()
      const authToken = new AuthToken('someToken', expiration)
      expect(authToken.needsRefreshing()).toBe(true)
    })

    test('returns false if token is not expired', () => {
      const expiration = new Date(Date.now() + 16000).toISOString()
      const authToken = new AuthToken('someToken', expiration)
      expect(authToken.needsRefreshing()).toBe(false)
    })

    test('returns true if no expiration time was given', () => {
      const authToken = new AuthToken('someToken')
      expect(authToken.needsRefreshing()).toBe(true)
    })
  })

  describe('fromResult', () => {
    test('returns new AuthToken instance', () => {
      const token = 'HelloNiceToken'
      const expiration = new Date().toISOString()
      const result: AuthTokenResult = {token, expiration}

      const authToken = AuthToken.fromResult(result)

      expect(authToken).toBeInstanceOf(AuthToken)
      expect(authToken.token).toBe(token)
      expect(authToken.expiration).toBe(expiration)
    })
  })

  describe('serialize', () => {
    test('returns AuthTokenResult for the token', () => {
      const token = 'HelloNiceToken'
      const expiration = new Date().toISOString()
      const authToken = new AuthToken(token, expiration)

      const serialized = authToken.serialize()

      expect(serialized).toStrictEqual({token, expiration})
    })
  })

  describe('deserialize', () => {
    test('converts an AuthTokenResult to an AuthToken', () => {
      const token = 'HelloNiceToken'
      const expiration = new Date().toISOString()
      const result: AuthTokenResult = {token, expiration}

      const authToken = AuthToken.deserialize(result)

      expect(authToken).toBeInstanceOf(AuthToken)
      expect(authToken.token).toBe(token)
      expect(authToken.expiration).toBe(expiration)
    })
  })

  describe('getAuthTokenValue', () => {
    test('returns overwrite value from local storage if it exists', async () => {
      const overwriteValue = 'Hello world'
      const authToken = new AuthToken()
      localStorage.setItem(authToken.authTokenLocalStorageOverwriteKey, overwriteValue)

      const result = await authToken.getAuthTokenValue()

      expect(result).toBe(overwriteValue)
      expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()
    })

    test('returns Authorization header value using token from local storage if it exists, is not expired, and there is no overwrite value', async () => {
      const token = 'HelloNiceToken'
      const expiration = new Date(Date.now() + 16000).toISOString()
      const authToken = new AuthToken()
      localStorage.removeItem(authToken.authTokenLocalStorageOverwriteKey)
      localStorage.setItem(authToken.authTokenLocalStorageKey, JSON.stringify({token, expiration}))

      const result = await authToken.getAuthTokenValue()

      expect(result).toBe(`GitHub-Bearer ${token}`)
      expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()
    })

    test('refreshes auth token from local storage when it is expired and there is no overwrite value', async () => {
      const oldToken = 'HelloNiceToken'
      const oldExpiration = new Date(Date.now() - 1000).toISOString()
      const authToken = new AuthToken()
      localStorage.removeItem(authToken.authTokenLocalStorageOverwriteKey)
      localStorage.setItem(
        authToken.authTokenLocalStorageKey,
        JSON.stringify({token: oldToken, expiration: oldExpiration}),
      )
      const newToken = 'afancynewtoken'
      const newExpiration = new Date(Date.now() + 16000).toISOString()
      mockVerifiedFetchJSON.mockResolvedValue({ok: true, json: () => ({token: newToken, expiration: newExpiration})})

      const result = await authToken.getAuthTokenValue()

      expect(result).toBe(`GitHub-Bearer ${newToken}`)
      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(authTokenUrl, {method: 'POST'})
    })

    test('fetches new auth token when none is stored in local storage and there is no overwrite value', async () => {
      const authToken = new AuthToken()
      localStorage.removeItem(authToken.authTokenLocalStorageOverwriteKey)
      localStorage.removeItem(authToken.authTokenLocalStorageKey)
      const newToken = 'afancynewtoken'
      const newExpiration = new Date(Date.now() + 16000).toISOString()
      mockVerifiedFetchJSON.mockResolvedValue({ok: true, json: () => ({token: newToken, expiration: newExpiration})})

      const result = await authToken.getAuthTokenValue()

      expect(result).toBe(`GitHub-Bearer ${newToken}`)
      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(authTokenUrl, {method: 'POST'})
    })
  })

  describe('getAuthToken', () => {
    test('returns auth token from local storage if it exists and is not expired', async () => {
      const token = 'HelloNiceToken'
      const expiration = new Date(Date.now() + 16000).toISOString()
      const authToken = new AuthToken()
      localStorage.setItem(authToken.authTokenLocalStorageKey, JSON.stringify({token, expiration}))

      const result = await authToken.getAuthToken()

      expect(result).toBeInstanceOf(AuthToken)
      expect(result.token).toBe(token)
      expect(result.expiration).toBe(expiration)
      expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()
    })

    test('fetches new auth token if the one in local storage is expired', async () => {
      const oldToken = 'HelloNiceToken'
      const oldExpiration = new Date(Date.now() - 1000).toISOString()
      const authToken = new AuthToken()
      localStorage.setItem(
        authToken.authTokenLocalStorageKey,
        JSON.stringify({token: oldToken, expiration: oldExpiration}),
      )
      const newToken = 'afancynewtoken'
      const newExpiration = new Date(Date.now() + 16000).toISOString()
      mockVerifiedFetchJSON.mockResolvedValue({ok: true, json: () => ({token: newToken, expiration: newExpiration})})

      const result = await authToken.getAuthToken()

      expect(result).toBeInstanceOf(AuthToken)
      expect(result.token).toBe(newToken)
      expect(result.expiration).toBe(newExpiration)
      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(authTokenUrl, {method: 'POST'})
    })

    test('fetches new auth token if there is none in local storage', async () => {
      const authToken = new AuthToken()
      localStorage.removeItem(authToken.authTokenLocalStorageKey)
      const newToken = 'afancynewtoken'
      const newExpiration = new Date(Date.now() + 16000).toISOString()
      mockVerifiedFetchJSON.mockResolvedValue({ok: true, json: () => ({token: newToken, expiration: newExpiration})})

      const result = await authToken.getAuthToken()

      expect(result).toBeInstanceOf(AuthToken)
      expect(result.token).toBe(newToken)
      expect(result.expiration).toBe(newExpiration)
      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(authTokenUrl, {method: 'POST'})
    })
  })
})

describe('default auth token', () => {
  test('is an instance of AuthToken', () => {
    expect(defaultAuthToken).toBeInstanceOf(AuthToken)
    expect(defaultAuthToken.token).toBeUndefined()
    expect(defaultAuthToken.expiration).toBeUndefined()
  })
})
