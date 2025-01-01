import {appendToQuery} from '../build-query'

describe('appendToQuery', () => {
  it('should return the original query if params object is empty', () => {
    const result = appendToQuery('status:open', {})
    expect(result).toBe('status:open')
  })

  it('should append a single parameter to the query', () => {
    const result = appendToQuery('status:open', {author: 'octocat'})
    expect(result).toBe('status:open author:octocat')
  })

  it('should append multiple parameters to the query', () => {
    const result = appendToQuery('status:open', {author: 'octocat', label: 'bug'})
    expect(result).toBe('status:open author:octocat label:bug')
  })

  it('should append parameters with array values', () => {
    const result = appendToQuery('status:open', {labels: ['bug', 'enhancement'], assignees: ['octocat', 'hubot']})
    expect(result).toBe('status:open labels:bug,enhancement assignees:octocat,hubot')
  })

  it('appends single parameter with whitespace', () => {
    expect(appendToQuery('status:open', {key: 'value with space'})).toBe('status:open key:"value with space"')
  })

  it('appends multiple parameters with and without whitespace', () => {
    const result = appendToQuery('status:open', {
      key1: 'value with space',
      key2: 'valueWithoutSpace',
    })
    expect(result).toBe('status:open key1:"value with space" key2:valueWithoutSpace')
  })

  it('should handle appending parameters to an empty query', () => {
    const result = appendToQuery('', {author: 'octocat'})
    expect(result).toBe('author:octocat')
  })
})
