// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {isValidInteger} from '../variable-transformers'

describe('isValidInteger', () => {
  test('returns true for a valid positive integer', () => {
    expect(isValidInteger('123')).toBe(true)
  })

  test('returns false for a non-integer string', () => {
    expect(isValidInteger('invalid')).toBe(false)
  })

  test('returns false for a string with decimal point', () => {
    expect(isValidInteger('123.45')).toBe(false)
  })

  test('returns false for an empty string', () => {
    expect(isValidInteger('')).toBe(false)
  })

  test('returns false for a string with special characters', () => {
    expect(isValidInteger('123.!invalid')).toBe(false)
  })
})
