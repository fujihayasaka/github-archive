import safeStorage from '@github-ui/safe-storage'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import {SparkAuthToken} from '../auth-token'
import {SparkAuthTokenProvider} from '../auth-token-provider'

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch')
jest.mock('@github-ui/safe-storage')

const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
const mockSafeStorage = safeStorage as jest.Mock
beforeAll(() => {
  jest.useFakeTimers()
  jest.setSystemTime(new Date('2024-07-02T19:59:47Z'))
})

afterAll(() => {
  jest.useRealTimers()
})
beforeEach(() => {
  jest.resetAllMocks()
})

describe('SparkAuthTokenProvider', () => {
  describe('getAuthToken', () => {
    test('mints a new auth token when no token is found in local storage', async () => {
      const mockTokenData = {token: 'exampleToken', expiration: '2024-07-02T19:53:11.000Z', ssoOrgIDs: []}
      mockResponse(mockTokenData)
      mockStorageValue()

      const provider = new SparkAuthTokenProvider([])
      const result = await provider.getAuthToken()
      const expectedResult = new SparkAuthToken(mockTokenData.token, mockTokenData.expiration, [])

      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
      expect(setItemMock).toHaveBeenCalled()
      expect(result).toEqual(expectedResult)
    })

    test('mints a new auth token when the stored token has expired', async () => {
      const expiredToken = {value: 'exampleToken', expiration: '2024-06-30T19:53:11.000Z', ssoOrgIDs: []}
      const newToken = {token: 'exampleToken', expiration: '2024-07-02T19:53:11.000Z', ssoOrgIDs: []}
      mockStorageValue(expiredToken)
      mockResponse(newToken)

      const provider = new SparkAuthTokenProvider([])
      const result = await provider.getAuthToken()
      const expectedResult = new SparkAuthToken(newToken.token, newToken.expiration, [])

      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
      expect(setItemMock).toHaveBeenCalled()
      expect(result).toEqual(expectedResult)
    })

    test('mints a new auth token when the sso status of an org has changed', async () => {
      const expiredToken = {value: 'exampleToken', expiration: '2024-06-30T19:53:11.000Z', ssoOrgIDs: ['1']}
      const newToken = {token: 'exampleToken', expiration: '2024-07-02T19:53:11.000Z', ssoOrgIDs: ['1', '2']}
      mockStorageValue(expiredToken)
      mockResponse(newToken)

      const provider = new SparkAuthTokenProvider(['1', '2'])
      const result = await provider.getAuthToken()
      const expectedResult = new SparkAuthToken(newToken.token, newToken.expiration, ['1', '2'])

      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
      expect(setItemMock).toHaveBeenCalled()
      expect(result).toEqual(expectedResult)
    })

    test('does not mint a new auth token when the auth token is valid and unexpired', async () => {
      const goodToken = {value: 'exampleToken', expiration: '2024-07-03T19:59:47Z', ssoOrgIDs: ['1']}
      mockStorageValue(goodToken)

      const provider = new SparkAuthTokenProvider(['1'])
      const result = await provider.getAuthToken()

      expect(result).toEqual(goodToken)
      expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()
      expect(setItemMock).not.toHaveBeenCalled()
    })

    test('does not mint multiple tokens if called multiple times', async () => {
      const mockTokenData = {token: 'exampleToken', expiration: '2024-07-02T19:53:11.000Z', ssoOrgIDs: []}
      mockResponse(mockTokenData)
      mockStorageValue()

      const provider = new SparkAuthTokenProvider([])
      provider.getAuthToken()
      await provider.getAuthToken()

      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    })
  })
})

function mockResponse(resp: unknown) {
  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    json: () => resp,
  })
}

const getItemMock = jest.fn()
const setItemMock = jest.fn()
function mockStorageValue(val?: {value: string; expiration: string; ssoOrgIDs: string[]}) {
  mockSafeStorage.mockReturnValue({
    getItem: getItemMock.mockReturnValue(val && JSON.stringify(val)),
    setItem: setItemMock,
  })
}
