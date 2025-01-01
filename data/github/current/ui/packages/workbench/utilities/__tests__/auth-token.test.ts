import type {AuthTokenResult} from '@github-ui/copilot-auth-token/auth-token'

import {SparkAuthToken} from '../auth-token'

describe('AuthToken', () => {
  describe('isExpired', () => {
    it('is true if the token is expired', () => {
      const token = new SparkAuthToken('deadbeef', '2020-01-01T00:00:00', [])

      expect(token.isExpired).toBeTruthy()
    })

    it('is false if the token is not expired', () => {
      const token = new SparkAuthToken('deadbeef', '2999-01-01T00:00:00', [])

      expect(token.isExpired).toBeFalsy()
    })

    it('has a 15 minute padding', () => {
      let expiry = new Date(Date.now() + 1000 * 60 * 13)
      let token = new SparkAuthToken('deadbeef', expiry.toISOString(), [])

      expect(token.isExpired).toBeTruthy()

      expiry = new Date(Date.now() + 1000 * 60 * 17)
      token = new SparkAuthToken('deadbeef', expiry.toISOString(), [])

      expect(token.isExpired).toBeFalsy()
    })
  })

  describe('fromResult', () => {
    it('builds an auth token correctly', () => {
      const result: AuthTokenResult = {
        token: 'deadbeef',
        expiration: '2020-01-01T00:00:00',
      }
      const orgIds = ['1234']

      const token = SparkAuthToken.fromResult(result, orgIds)

      expect(token.value).toEqual(result.token)
      expect(token.expiration).toEqual(result.expiration)
      expect(token.ssoOrgIDs).toEqual(['1234'])
    })
  })

  describe('deserialize', () => {
    it('builds an AuthToken correctly', () => {
      const token = SparkAuthToken.deserialize({
        value: 'deadbeef',
        expiration: '2020-01-01T00:00:00',
        ssoOrgIDs: ['1234'],
      })

      expect(token.value).toEqual('deadbeef')
      expect(token.expiration).toEqual('2020-01-01T00:00:00')
      expect(token.ssoOrgIDs).toEqual(['1234'])
    })
  })
})
