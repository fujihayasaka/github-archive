import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {formatPublishedDate, appendFeatureFlagsToUrl, replacePageNumberInUrl} from '../../lib/utils'

describe('formatPublishedDate', () => {
  it('returns null if no date is provided', () => {
    expect(formatPublishedDate()).toBeNull()
  })

  it('returns the formatted date', () => {
    const date = '2024-08-20'
    const expected = 'August 20, 2024'
    expect(formatPublishedDate(date)).toBe(expected)
  })

  it('returns the formatted date in the specified locale', () => {
    const date = '2024-08-20'
    const expected = '20 août 2024'
    expect(formatPublishedDate(date, 'fr-FR')).toBe(expected)
  })

  it('returns null for an invalid date format', () => {
    const invalidDate = '2024-13-01' // Invalid month
    expect(formatPublishedDate(invalidDate)).toBeNull()
  })

  it('returns null for an invalid date string', () => {
    const invalidDate = 'invalid-date-string'
    expect(formatPublishedDate(invalidDate)).toBeNull()
  })

  it('returns null for an empty date string', () => {
    expect(formatPublishedDate('')).toBeNull()
  })

  it('handles a leap year date correctly', () => {
    const date = '2024-02-29' // Leap year
    const expected = 'February 29, 2024'
    expect(formatPublishedDate(date)).toBe(expected)
  })

  it('returns null for a date in the wrong format', () => {
    const wrongFormat = '20-08-2024' // Incorrect format
    expect(formatPublishedDate(wrongFormat)).toBeNull()
  })
})

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

describe('replacePageNumberInUrl', () => {
  it('replaces the page number in the URL', () => {
    const url = 'http://example.com?page=2'
    const pageNumber = 3
    const expected = 'http://example.com/?page=3'
    expect(replacePageNumberInUrl(url, pageNumber)).toBe(expected)
  })

  it('removes the page parameter if the page number is 1', () => {
    const url = 'http://example.com?page=1'
    const pageNumber = 1
    const expected = 'http://example.com/'
    expect(replacePageNumberInUrl(url, pageNumber)).toBe(expected)
  })

  it('adds the page parameter if it does not exist', () => {
    const url = 'http://example.com'
    const pageNumber = 2
    const expected = 'http://example.com/?page=2'
    expect(replacePageNumberInUrl(url, pageNumber)).toBe(expected)
  })

  it('handles URLs with other query parameters', () => {
    const url = 'http://example.com?foo=bar'
    const pageNumber = 2
    const expected = 'http://example.com/?foo=bar&page=2'
    expect(replacePageNumberInUrl(url, pageNumber)).toBe(expected)
  })

  it('prepends the url origin if not present', () => {
    const url = '/foo'
    const pageNumber = 2
    const expected = `${ssrSafeLocation.origin}/foo?page=2`
    expect(replacePageNumberInUrl(url, pageNumber)).toBe(expected)
  })
})
