import {beforeAll, describe, expect, it, beforeEach} from '@github-ui/tests'
import {addBaseFetchHeaders, getAppTypeHeader, getBaseFetchHeaders} from '../fetch-headers'
import {addValidNonce} from '@github-ui/fetch-nonce'
import {vi} from 'vitest'
import {featureFlag} from '@github-ui/feature-flags'

beforeAll(async function () {
  addValidNonce('12345')
})

vi.mock('@github-ui/feature-flags')

describe('fetch-headers', () => {
  describe('with feature flag disabled', () => {
    beforeEach(() => {
      vi.mocked(featureFlag.isFeatureEnabled).mockReturnValue(false)
    })

    it('adds X-Requested-With and X-Fetch-Nonce headers', () => {
      const headers = getBaseFetchHeaders()
      expect(headers).toEqual({
        'X-Requested-With': 'XMLHttpRequest',
        'X-Fetch-Nonce': '12345',
      })
    })

    it('adds X-Fetch-Nonce-To-Validate header when validating a nonce', () => {
      const headers = getBaseFetchHeaders('54321')
      expect(headers).toEqual({
        'X-Requested-With': 'XMLHttpRequest',
        'X-Fetch-Nonce': '12345',
        'X-Fetch-Nonce-To-Validate': '54321',
      })
    })

    it('adds base headers to Headers object', () => {
      const headers = new Headers()
      addBaseFetchHeaders(headers, '54312')

      expect(headers.get('X-Requested-With')).toEqual('XMLHttpRequest')
      expect(headers.get('X-Fetch-Nonce')).toEqual('12345')
      expect(headers.get('X-Fetch-Nonce-To-Validate')).toEqual('54312')
    })

    it('getAppTypeHeader returns undefined', () => {
      expect(getAppTypeHeader('navigator')).toBeUndefined()
    })
  })

  describe('with feature flag enabled', () => {
    beforeEach(() => {
      vi.mocked(featureFlag.isFeatureEnabled).mockReturnValue(true)
    })

    it('adds X-Client-Version header', () => {
      const headers = getBaseFetchHeaders()
      expect(headers).toEqual({
        'X-Requested-With': 'XMLHttpRequest',
        'X-Fetch-Nonce': '12345',
        'X-GitHub-Client-Version': '',
      })
    })

    it('getAppTypeHeader returns X-GitHub-App-Type for app type it was passed', () => {
      expect(getAppTypeHeader('navigator')).toEqual({'X-GitHub-App-Type': 'navigator'})
      expect(getAppTypeHeader('dataRouter')).toEqual({'X-GitHub-App-Type': 'dataRouter'})
    })
  })
})
