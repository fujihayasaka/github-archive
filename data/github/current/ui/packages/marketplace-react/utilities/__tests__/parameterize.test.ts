import {parameterize} from '../parameterize'

describe('parameterize', () => {
  it('converts a string to URL-friendly format', () => {
    expect(parameterize('Hello World')).toBe('hello-world')
  })

  it('handles strings with multiple spaces', () => {
    expect(parameterize('Hello   World')).toBe('hello-world')
  })

  it('handles strings with leading and trailing spaces', () => {
    expect(parameterize('   Hello World   ')).toBe('hello-world')
  })

  it('handles strings with special characters', () => {
    expect(parameterize('Hello@World!')).toBe('hello@world!')
  })
})
