import {prefixUrl, isValidAndSafeUrl, containsSafeContent} from '../url'

describe('prefixUrl', () => {
  test('prefixes https:// to string beginning with www.', () => {
    expect(prefixUrl('www.something.com')).toBe('https://www.something.com')
  })

  test(`leaves string that don't begin with www. intact`, () => {
    expect(prefixUrl('https://something.com')).toBe('https://something.com')
    expect(prefixUrl('https://www.something.com')).toBe('https://www.something.com')
  })
})

describe('isValidUrl', () => {
  test('return true for a https URL', () => {
    expect(isValidAndSafeUrl('https://www.something.com')).toBe(true)
  })

  test('returns true for a http URL', () => {
    expect(isValidAndSafeUrl('http://www.something.com')).toBe(true)
  })

  test('return false for an invalid URL', () => {
    expect(isValidAndSafeUrl('test')).toBe(false)
  })

  test('returns true for a safe URL', () => {
    const safeUrl = 'https://example.com'

    const result = containsSafeContent(safeUrl)
    expect(result).toBe(true)
  })

  test('returns false for an unsafe URL', () => {
    const unsafeUrl = 'https://example.com<script>alert("XSS")</script>'

    const result = containsSafeContent(unsafeUrl)
    expect(result).toBe(false)
  })
})
