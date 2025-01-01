import {tokenizeQuery} from '../tokenize-query'

describe('tokenizeQuery', () => {
  it('should tokenize query with multiple qualifiers and term', () => {
    const query = 'repo:github user:octocat is:public test'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'repo', values: ['github'], raw: 'repo:github'},
      {type: 'filter', key: 'user', values: ['octocat'], raw: 'user:octocat'},
      {type: 'filter', key: 'is', values: ['public'], raw: 'is:public'},
      {type: 'text', value: 'test'},
    ])
  })

  it('should correctly trim when there are multiple whitespaces', () => {
    const query = '  repo:github   user:octocat  is:public   test  '
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'repo', values: ['github'], raw: 'repo:github'},
      {type: 'filter', key: 'user', values: ['octocat'], raw: 'user:octocat'},
      {type: 'filter', key: 'is', values: ['public'], raw: 'is:public'},
      {type: 'text', value: 'test'},
    ])
  })

  it('should tokenize query with multiple similar qualifiers and term', () => {
    const query = 'repo:github repo:octocat is:public test'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'repo', values: ['github'], raw: 'repo:github'},
      {type: 'filter', key: 'repo', values: ['octocat'], raw: 'repo:octocat'},
      {type: 'filter', key: 'is', values: ['public'], raw: 'is:public'},
      {type: 'text', value: 'test'},
    ])
  })

  it('should handle values with whitespace if enclosed in quotation marks', () => {
    const query = 'repo:"github repo" user:octocat" prop.env:"prod::1"'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'repo', values: ['"github repo"'], raw: 'repo:"github repo"'},
      {type: 'filter', key: 'user', values: ['octocat" prop.env:"prod::1"'], raw: 'user:octocat" prop.env:"prod::1"'},
    ])
  })

  it('supports comma syntax', () => {
    const query = 'props.env:prod,"test a"'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'props.env', values: ['prod', '"test a"'], raw: 'props.env:prod,"test a"'},
    ])
  })

  it('supports dash in keys', () => {
    const query = 'help-wanted-issues:3'
    const result = tokenizeQuery(query)
    expect(result).toEqual([{type: 'filter', key: 'help-wanted-issues', values: ['3'], raw: 'help-wanted-issues:3'}])
  })

  it('supports negation', () => {
    const query = '-user:octocat'
    const result = tokenizeQuery(query)
    expect(result).toEqual([{type: 'filter', key: '-user', values: ['octocat'], raw: '-user:octocat'}])
  })

  it('should handle qualifier with double semicolon', () => {
    const query = 'repo::octocat'
    const result = tokenizeQuery(query)
    expect(result).toEqual([{type: 'filter', key: 'repo', values: [':octocat'], raw: 'repo::octocat'}])
  })

  it('should handle key without value', () => {
    const query = 'repo: :github'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'repo', values: [''], raw: 'repo:'},
      {type: 'text', value: ':github'},
    ])
  })
})
