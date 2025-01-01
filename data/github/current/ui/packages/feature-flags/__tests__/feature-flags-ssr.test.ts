/** @jest-environment node */
import {mockClientEnv} from '@github-ui/client-env/mock'
import {getEnabledFeatures, isFeatureEnabled} from '../feature-flags'
import type {JSFeatureFlag} from '../client-feature-flags'

describe('isFeatureEnabled', () => {
  it('should return true if the feature is enabled', () => {
    mockClientEnv({
      featureFlags: ['foo'],
    })

    expect(isFeatureEnabled('foo' as JSFeatureFlag)).toBe(true)
    expect(isFeatureEnabled('bar' as JSFeatureFlag)).toBe(false)
  })
})

describe('getEnabledFeatures', () => {
  it('should return an array of enabled features', () => {
    mockClientEnv({
      featureFlags: ['foo', 'bar', 'foo_bar'],
    })

    expect(getEnabledFeatures()).toEqual(['foo', 'bar', 'foo_bar'])
  })
})
