import {getCustomPropertiesProvider, getRepoFilterProviders} from '@github-ui/repos-filter/providers'

import {pruneQuery, validateQueryKeys} from '../validate-query'

const propertiesProvider = getCustomPropertiesProvider([
  {propertyName: 'env', valueType: 'string'},
  {propertyName: 'qty', valueType: 'single_select', allowedValues: ['one', 'two', 'another value']},
])

describe('validateQueryKeys', () => {
  it('returns an empty list when no providers are provided', () => {
    const result = validateQueryKeys('key:value')
    expect(result).toEqual([])
  })

  it('returns invalid segments', () => {
    const providers = getRepoFilterProviders(['fork'])
    const query = 'fork:true invalid:value test'
    const result = validateQueryKeys(query, providers)

    expect(result).toEqual([
      {type: 'filter', key: 'invalid', values: ['value'], raw: 'invalid:value', isNegated: false},
      {type: 'text', value: 'test'},
    ])
  })

  it('supports custom properties', () => {
    const query = 'props.env:test props.invalid:value'
    const result = validateQueryKeys(query, [propertiesProvider])

    expect(result).toEqual([
      {type: 'filter', key: 'props.invalid', values: ['value'], raw: 'props.invalid:value', isNegated: false},
    ])
  })

  it('supports negation', () => {
    const providers = getRepoFilterProviders(['fork'])
    const query = '-fork:true'
    const result = validateQueryKeys(query, providers)

    expect(result).toEqual([])
  })
})

describe('pruneQuery', () => {
  it('returns an empty list when no providers are provided', () => {
    const result = pruneQuery('key:value', [])
    expect(result).toEqual([])
  })

  it('supports custom properties', () => {
    const query = 'props.env:test props.qty:one props.qty:drop props.unknown:ignore'
    const result = pruneQuery(query, [propertiesProvider])

    expect(result).toEqual([
      {type: 'filter', key: 'props.env', values: ['test'], raw: 'props.env:test', isNegated: false},
      {type: 'filter', key: 'props.qty', values: ['one'], raw: 'props.qty:one', isNegated: false},
    ])
  })

  it('supports custom properties with multiple words values', () => {
    const query = 'props.qty:"another value"'
    const result = pruneQuery(query, [propertiesProvider])

    expect(result).toEqual([
      {
        type: 'filter',
        key: 'props.qty',
        values: ['"another value"'],
        raw: 'props.qty:"another value"',
        isNegated: false,
      },
    ])
  })

  it('drops duplicated keys that are not multiKey', () => {
    const query = 'visibility:public visibility:private -visibility:private -visibility:internal'
    const providers = getRepoFilterProviders(['visibility'])
    const result = pruneQuery(query, providers, true)

    expect(result).toEqual([
      {type: 'filter', key: 'visibility', values: ['public'], raw: 'visibility:public', isNegated: false},
    ])
  })

  it('drops duplicated keys that are not multiKey (negative first)', () => {
    const query = '-visibility:private -visibility:internal visibility:public visibility:private'
    const providers = getRepoFilterProviders(['visibility'])
    const result = pruneQuery(query, providers, true)

    expect(result).toEqual([
      {type: 'filter', key: 'visibility', values: ['private'], raw: '-visibility:private', isNegated: true},
    ])
  })

  it('keys can be duplicated when are multiKey', () => {
    const propertiesProviderWithMulityKey = getCustomPropertiesProvider([
      {propertyName: 'multi', valueType: 'multi_select', allowedValues: ['one', 'two', 'three']},
    ])
    const query = 'props.multi:one props.multi:two -props.multi:three'
    const result = pruneQuery(query, [propertiesProviderWithMulityKey], true)

    expect(result).toEqual([
      {type: 'filter', key: 'props.multi', values: ['one'], raw: 'props.multi:one', isNegated: false},
      {type: 'filter', key: 'props.multi', values: ['two'], raw: 'props.multi:two', isNegated: false},
      {type: 'filter', key: 'props.multi', values: ['three'], raw: '-props.multi:three', isNegated: true},
    ])
  })
})
