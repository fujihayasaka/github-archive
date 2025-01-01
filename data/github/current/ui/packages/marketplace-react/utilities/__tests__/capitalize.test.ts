import {capitalize} from '../capitalize'

describe('capitalize', () => {
  it('capitalizes the first letter of a string', () => {
    expect(capitalize('hello')).toBe('Hello')
  })

  it('only capitalizes the first letter of a string', () => {
    expect(capitalize('hello world')).toBe('Hello world')
  })

  it('returns the original string if it is empty', () => {
    expect(capitalize('')).toBe('')
  })

  it('returns the original string if it is not a string', () => {
    expect(capitalize(123 as any)).toBe(123)
  })
})
