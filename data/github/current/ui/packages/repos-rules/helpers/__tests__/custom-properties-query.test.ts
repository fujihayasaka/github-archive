import {buildQueryForProperty, buildQueryForAllProperties, queryToPropertyParameters} from '../custom-properties-query'
import type {PropertyConfiguration, RepositoryPropertyParameters} from '../../types/rules-types'

describe('buildQueryForAllProperties', () => {
  const properties: RepositoryPropertyParameters = {
    include: [
      {
        name: 'language',
        source: 'system',
        property_values: ['go'],
      },
    ],
    exclude: [
      {
        name: 'database',
        source: 'custom',
        property_values: ['postgresql'],
      },
    ],
  }

  it('builds a query for a repo with no properties', () => {
    expect(buildQueryForAllProperties({include: [], exclude: []} as RepositoryPropertyParameters)).toEqual('')
  })

  it('builds a query for a repo', () => {
    expect(buildQueryForAllProperties(properties)).toEqual('language:go -props.database:postgresql')
  })

  it('builds a query for a repo with multiple include properties', () => {
    const multiValueProperties: RepositoryPropertyParameters = {
      include: [
        ...properties.include,
        {
          name: 'database',
          source: 'custom',
          property_values: ['mysql', 'postgresql'],
        },
      ],
      exclude: [],
    }

    expect(buildQueryForAllProperties(multiValueProperties)).toEqual('language:go props.database:mysql,postgresql')
  })

  it('wraps values with special characters in quotes', () => {
    const params: RepositoryPropertyParameters = {
      include: [{name: 'env', source: 'custom', property_values: ['two words', '(beta)', 'staging,testing']}],
      exclude: [],
    }

    const result = buildQueryForAllProperties(params)

    const expectedQuery = 'props.env:"two words","(beta)","staging,testing"'
    expect(result).toEqual(expectedQuery)
  })

  it('double quotes are not escaped', () => {
    const params: RepositoryPropertyParameters = {
      include: [{name: 'env', source: 'custom', property_values: ['"value']}],
      exclude: [],
    }

    const result = buildQueryForAllProperties(params)

    const expectedQuery = 'props.env:"value'
    expect(result).toEqual(expectedQuery)
  })
})

describe('buildQueryForProperty', () => {
  it('builds a query for a system property', () => {
    const property: PropertyConfiguration = {
      name: 'fork',
      source: 'system',
      property_values: ['true'],
    }
    expect(buildQueryForProperty(property, '')).toEqual('fork:true')
    expect(buildQueryForProperty(property, '-')).toEqual('-fork:true')
  })

  it('builds a query for a custom property', () => {
    const property: PropertyConfiguration = {
      name: 'database',
      source: 'custom',
      property_values: ['mysql'],
    }
    expect(buildQueryForProperty(property, '')).toEqual('props.database:mysql')
    expect(buildQueryForProperty(property, '-')).toEqual('-props.database:mysql')
  })

  it('builds a query for multiple values', () => {
    const property: PropertyConfiguration = {
      name: 'database',
      source: 'custom',
      property_values: ['mysql', 'postgresql'],
    }
    expect(buildQueryForProperty(property, '')).toEqual('props.database:mysql,postgresql')
    expect(buildQueryForProperty(property, '-')).toEqual('-props.database:mysql,postgresql')
  })

  it('builds a query for properties with space in the value', () => {
    const property: PropertyConfiguration = {
      name: 'database',
      source: 'custom',
      property_values: ['dim grey', 'blue', 'carbon black'],
    }
    expect(buildQueryForProperty(property, '')).toEqual('props.database:"dim grey",blue,"carbon black"')
    expect(buildQueryForProperty(property, '-')).toEqual('-props.database:"dim grey",blue,"carbon black"')
  })
})

describe('queryToPropertyParameters', () => {
  it('parses supported keys and ignores unsupported', () => {
    const inclusion = 'props.env:dev language:javascript fork:true visibility:public unsupported:key text'
    const exclusion = '-props.env:dev -language:javascript -fork:true -visibility:public -unsupported:key'

    const query = `${inclusion} ${exclusion}`
    const result = queryToPropertyParameters(query)
    expect(result).toEqual({
      include: [
        {name: 'env', source: 'custom', property_values: ['dev']},
        {name: 'language', source: 'system', property_values: ['javascript']},
        {name: 'fork', source: 'system', property_values: ['true']},
        {name: 'visibility', source: 'system', property_values: ['public']},
      ],
      exclude: [
        {name: 'env', source: 'custom', property_values: ['dev']},
        {name: 'language', source: 'system', property_values: ['javascript']},
        {name: 'fork', source: 'system', property_values: ['true']},
        {name: 'visibility', source: 'system', property_values: ['public']},
      ],
    })
  })

  it('supports any qualifier for properties: properties, props, p', () => {
    const query = 'props.env:prod p.team:sales properties.id:"123-abc"'
    const result = queryToPropertyParameters(query)
    expect(result).toEqual({
      include: [
        {name: 'env', source: 'custom', property_values: ['prod']},
        {name: 'team', source: 'custom', property_values: ['sales']},
        {name: 'id', source: 'custom', property_values: ['123-abc']},
      ],
      exclude: [],
    })
  })

  it('parses multiple values for a single key', () => {
    const query = 'language:javascript,typescript'
    const result = queryToPropertyParameters(query)
    expect(result).toEqual({
      include: [{name: 'language', source: 'system', property_values: ['javascript', 'typescript']}],
      exclude: [],
    })
  })

  it('supports multiple dots in the key', () => {
    const query = 'props.a.b.c:test'
    const result = queryToPropertyParameters(query)
    expect(result).toEqual({
      include: [{name: 'a.b.c', source: 'custom', property_values: ['test']}],
      exclude: [],
    })
  })

  it('supports dashes in the value', () => {
    const query = 'props.env:d-e-v'
    const result = queryToPropertyParameters(query)
    expect(result).toEqual({
      include: [{name: 'env', source: 'custom', property_values: ['d-e-v']}],
      exclude: [],
    })
  })

  it('creates a condition for every key occurrence', () => {
    const query = 'props.env:dev props.env:prod'
    const result = queryToPropertyParameters(query)
    expect(result).toEqual({
      include: [
        {name: 'env', source: 'custom', property_values: ['dev']},
        {name: 'env', source: 'custom', property_values: ['prod']},
      ],
      exclude: [],
    })
  })

  it('ignores `no` qualifier', () => {
    const query = 'no:props.env'
    const result = queryToPropertyParameters(query)
    expect(result).toEqual({
      include: [],
      exclude: [],
    })
  })

  it('handles empty query string', () => {
    const query = ''
    const result = queryToPropertyParameters(query)
    expect(result).toEqual({
      include: [],
      exclude: [],
    })
  })
})
