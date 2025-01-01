import {parseData} from '../parse-data'

describe('parseData', () => {
  it('should handle number input', () => {
    const result = parseData(42)
    expect(result).toEqual({data: 42, type: 'number'})
  })

  it('should parse string containing number', () => {
    const result = parseData('42')
    expect(result).toEqual({data: 42, type: 'number'})
  })

  it('should parse JSON object', () => {
    const jsonObject = '{"name":"test","value":123}'
    const result = parseData(jsonObject)
    expect(result).toEqual({
      data: {name: 'test', value: 123},
      type: 'object',
    })
  })

  it('should parse array of JSON objects', () => {
    const jsonObject = '[{"name":"test","value":123},{"name":"test2","value":1234}]'
    const result = parseData(jsonObject)
    // use `toMatchObject` here instead of `toEqual` to allow for dynamic IDs
    // It works correctly, unless the test fails, in which case you get an unrelated error.
    // see: https://github.com/jestjs/jest/issues/15078
    expect(result).toMatchObject({
      data: [
        {name: 'test', value: 123, id: expect.any(String)},
        {name: 'test2', value: 1234, id: expect.any(String)},
      ],
      allKeys: ['name', 'value', 'id'],
      type: 'table',
    })
  })

  it('should parse simple JSON array of numbers', () => {
    const jsonArray = '[1,2,3]'
    const result = parseData(jsonArray)
    expect(result).toEqual({
      data: [1, 2, 3],
      type: 'array',
    })
  })

  it('should parse simple JSON array of strings', () => {
    const jsonArray = '["one","two","three"]'
    const result = parseData(jsonArray)
    expect(result).toEqual({
      data: ['one', 'two', 'three'],
      type: 'array',
    })
  })

  it('should parse JSON empty JSON array', () => {
    const jsonArray = '[]'
    const result = parseData(jsonArray)
    expect(result).toEqual({
      data: [],
      type: 'array',
    })
  })

  it('should parse boolean value as string', () => {
    const result = parseData('true')
    expect(result).toEqual({data: true, type: 'string'})
  })

  it('should handle non-parseable string', () => {
    const result = parseData('not json')
    expect(result).toEqual({data: 'not json', type: 'string'})
  })

  it('should handle empty string', () => {
    const result = parseData('')
    expect(result).toEqual({data: '', type: 'string'})
  })
})
