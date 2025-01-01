import {isPrsOnly} from '../utils/query'

describe('isPrsOnly', () => {
  it('should return true when query contains only PR qualifiers', () => {
    const query = 'is:pr'
    expect(isPrsOnly(query)).toBe(true)
  })

  it('should return false when query contains only issue qualifiers', () => {
    const query = 'is:issue'
    expect(isPrsOnly(query)).toBe(false)
  })

  it('should return false when query contains both PR and issue qualifiers', () => {
    const query = 'is:pr is:issue'
    expect(isPrsOnly(query)).toBe(false)
  })

  it('should return true when query contains only pull-request qualifiers', () => {
    const query = 'type:pull-request'
    expect(isPrsOnly(query)).toBe(true)
  })

  it('should return false when query contains neither PR nor issue qualifiers', () => {
    const query = 'is:open'
    expect(isPrsOnly(query)).toBe(false)
  })

  it('should return true when query contains mixed qualifiers but only PR related', () => {
    const query = 'is:pr type:pull-request'
    expect(isPrsOnly(query)).toBe(true)
  })

  it('should return false when query contains mixed qualifiers including issue', () => {
    const query = 'is:pr type:issue'
    expect(isPrsOnly(query)).toBe(false)
  })

  it('should return false when query is empty', () => {
    const query = ''
    expect(isPrsOnly(query)).toBe(false)
  })

  it('should return false when query contains unrelated qualifiers', () => {
    const query = 'author:octocat'
    expect(isPrsOnly(query)).toBe(false)
  })
})
