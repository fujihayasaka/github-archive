import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {appendFeatureFlagsToUrl} from '../../lib/utils'

describe('appendFeatureFlagsToUrl', () => {
  it('appends feature flags if they do not exist in the URL', () => {
    const url = 'http://example.com'
    const featureFlags = 'new-feature'
    const expected = 'http://example.com/?_features=new-feature'
    expect(appendFeatureFlagsToUrl(url, featureFlags)).toBe(expected)
  })

  it('replaces feature flags if they exist in the URL', () => {
    const url = 'http://example.com?_features=old-feature'
    const featureFlags = 'new-feature'
    const expected = 'http://example.com/?_features=new-feature'
    expect(appendFeatureFlagsToUrl(url, featureFlags)).toBe(expected)
  })

  it('appends feature flags if other query parameters exist in the URL', () => {
    const url = 'http://example.com?foo=bar'
    const featureFlags = 'new-feature'
    const expected = 'http://example.com/?foo=bar&_features=new-feature'
    expect(appendFeatureFlagsToUrl(url, featureFlags)).toBe(expected)
  })

  it('prepends the url origin if not present', () => {
    const url = '/foo'
    const featureFlags = 'new-feature'
    const expected = `${ssrSafeLocation.origin}/foo?_features=new-feature`
    expect(appendFeatureFlagsToUrl(url, featureFlags)).toBe(expected)
  })
})
