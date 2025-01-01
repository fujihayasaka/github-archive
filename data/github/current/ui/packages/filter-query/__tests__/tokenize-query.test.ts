import {tokenizeQuery} from '../tokenize-query'

describe('tokenizeQuery', () => {
  it('should tokenize query with multiple qualifiers and term', () => {
    const query = 'repo:github user:octocat is:public test'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'repo', values: ['github'], raw: 'repo:github', isNegated: false},
      {type: 'filter', key: 'user', values: ['octocat'], raw: 'user:octocat', isNegated: false},
      {type: 'filter', key: 'is', values: ['public'], raw: 'is:public', isNegated: false},
      {type: 'text', value: 'test'},
    ])
  })

  it('should correctly trim when there are multiple whitespaces', () => {
    const query = '  repo:github   user:octocat  is:public   test  '
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'repo', values: ['github'], raw: 'repo:github', isNegated: false},
      {type: 'filter', key: 'user', values: ['octocat'], raw: 'user:octocat', isNegated: false},
      {type: 'filter', key: 'is', values: ['public'], raw: 'is:public', isNegated: false},
      {type: 'text', value: 'test'},
    ])
  })

  it('should tokenize query with multiple similar qualifiers and term', () => {
    const query = 'repo:github repo:octocat is:public test'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'repo', values: ['github'], raw: 'repo:github', isNegated: false},
      {type: 'filter', key: 'repo', values: ['octocat'], raw: 'repo:octocat', isNegated: false},
      {type: 'filter', key: 'is', values: ['public'], raw: 'is:public', isNegated: false},
      {type: 'text', value: 'test'},
    ])
  })

  it('should handle values with whitespace if enclosed in quotation marks', () => {
    const query = 'repo:"github repo" user:octocat" prop.env:"prod::1"'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'repo', values: ['"github repo"'], raw: 'repo:"github repo"', isNegated: false},
      {
        type: 'filter',
        key: 'user',
        values: ['octocat" prop.env:"prod::1"'],
        raw: 'user:octocat" prop.env:"prod::1"',
        isNegated: false,
      },
    ])
  })

  it('should handle custom properties values with whitespace', () => {
    const query = 'props.env:"test a"'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {
        type: 'filter',
        key: 'props.env',
        values: ['"test a"'],
        raw: 'props.env:"test a"',
        isNegated: false,
      },
    ])
  })

  it('supports comma syntax', () => {
    const query = 'props.env:prod,"test a"'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {
        type: 'filter',
        key: 'props.env',
        values: ['prod', '"test a"'],
        raw: 'props.env:prod,"test a"',
        isNegated: false,
      },
    ])
  })

  it('supports dash in keys', () => {
    const query = 'help-wanted-issues:3'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'help-wanted-issues', values: ['3'], raw: 'help-wanted-issues:3', isNegated: false},
    ])
  })

  it('supports negation', () => {
    const query = '-user:octocat'
    const result = tokenizeQuery(query)
    expect(result).toEqual([{type: 'filter', key: 'user', values: ['octocat'], raw: '-user:octocat', isNegated: true}])
  })

  it('should handle qualifier with double semicolon', () => {
    const query = 'repo::octocat'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'repo', values: [':octocat'], raw: 'repo::octocat', isNegated: false},
    ])
  })

  it('should handle key without value', () => {
    const query = 'repo: :github'
    const result = tokenizeQuery(query)
    expect(result).toEqual([
      {type: 'filter', key: 'repo', values: [''], raw: 'repo:', isNegated: false},
      {type: 'text', value: ':github'},
    ])
  })

  it('should return plain query if it exceeds 1000 characters', () => {
    const longQuery = 'a'.repeat(1001)
    const result = tokenizeQuery(longQuery)
    expect(result).toEqual([{type: 'text', value: longQuery}])
  })
})
