import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {describe, expect, it} from '@github-ui/tests'

import {queryKeyHashFn} from '../query-key-hash-fn'

describe('queryKeyHashFn', () => {
  describe('tests from https://github.com/TanStack/query/blob/256624af671772732c7e11c2689bb1697ee7e72c/packages/query-core/src/__tests__/utils.test.tsx#L501-L532', () => {
    it('should hash primitives correctly', () => {
      expect(queryKeyHashFn(['test'])).toEqual(JSON.stringify(['test']))
      expect(queryKeyHashFn([123])).toEqual(JSON.stringify([123]))
      expect(queryKeyHashFn([null])).toEqual(JSON.stringify([null]))
    })

    it('should hash objects with sorted keys consistently', () => {
      const key1 = [{b: 2, a: 1}]
      const key2 = [{a: 1, b: 2}]

      const hash1 = queryKeyHashFn(key1)
      const hash2 = queryKeyHashFn(key2)

      expect(hash1).toEqual(hash2)
      expect(hash1).toEqual(JSON.stringify([{a: 1, b: 2}]))
    })

    it('should hash arrays consistently', () => {
      const arr1 = [{b: 2, a: 1}, 'test', 123]
      const arr2 = [{a: 1, b: 2}, 'test', 123]

      expect(queryKeyHashFn(arr1)).toEqual(queryKeyHashFn(arr2))
    })

    it('should handle nested objects with sorted keys', () => {
      const nested1 = [{a: {d: 4, c: 3}, b: 2}]
      const nested2 = [{b: 2, a: {c: 3, d: 4}}]

      expect(queryKeyHashFn(nested1)).toEqual(queryKeyHashFn(nested2))
    })
  })

  it('should stringify primitive query keys', () => {
    expect(queryKeyHashFn(['users'])).toBe('["users"]')
    expect(queryKeyHashFn(['user', 123])).toBe('["user",123]')
    expect(queryKeyHashFn(['user', true])).toBe('["user",true]')
    expect(queryKeyHashFn(['user', null])).toBe('["user",null]')
  })

  it('should sort object keys for consistent hashing', () => {
    // Objects with same properties in different order should hash the same
    const obj1 = {name: 'user1', id: 123}
    const obj2 = {id: 123, name: 'user1'}

    expect(queryKeyHashFn(['users', obj1])).toBe(queryKeyHashFn(['users', obj2]))
    expect(queryKeyHashFn(['users', obj1])).toBe('["users",{"id":123,"name":"user1"}]')
  })

  it('should handle nested objects by sorting keys at each level', () => {
    const nestedObj = {
      user: {
        details: {
          lastName: 'Doe',
          firstName: 'John',
        },
        id: 123,
      },
    }

    // Here we're testing that the nested keys are also sorted
    expect(queryKeyHashFn(['user', nestedObj])).toBe(
      '["user",{"user":{"details":{"firstName":"John","lastName":"Doe"},"id":123}}]',
    )
  })

  it('should handle URLSearchParams by sorting parameters', () => {
    // URLSearchParams with same parameters in different order should hash the same
    const params1 = new URLSearchParams('b=2&a=1')
    const params2 = new URLSearchParams('a=1&b=2')

    expect(queryKeyHashFn(['search', params1])).toBe(queryKeyHashFn(['search', params2]))
    expect(queryKeyHashFn(['search', params1])).toBe('["search","a=1&b=2"]')
  })

  it('should handle arrays within query keys', () => {
    expect(queryKeyHashFn(['users', [1, 2, 3]])).toBe('["users",[1,2,3]]')

    // Array of objects should have each object's keys sorted
    const arrayOfObjects = [
      {id: 2, name: 'Jane'},
      {name: 'John', id: 1},
    ]

    expect(queryKeyHashFn(['users', arrayOfObjects])).toBe('["users",[{"id":2,"name":"Jane"},{"id":1,"name":"John"}]]')
  })

  it('should handle complex query keys with mixed types', () => {
    const complexKey = [
      'users',
      {filters: {active: true, role: 'admin'}, sort: 'name'},
      new URLSearchParams('page=2&perPage=10'),
      [1, 2, 3],
    ]

    expect(queryKeyHashFn(complexKey)).toBe(
      '["users",{"filters":{"active":true,"role":"admin"},"sort":"name"},"page=2&perPage=10",[1,2,3]]',
    )
  })

  it('should handle Relay environment objects with consistent hashing', () => {
    /**
     * Even with the circular references, the hash function should work and be consistent
     * see related pr: https://github.com/github/github/pull/373826
     */
    expect(queryKeyHashFn([relayEnvironmentWithMissingFieldHandlerForNode()])).toBe('["RelayModernEnvironment()"]')
  })

  it('should handle objects with special types', () => {
    // Test with Date objects
    const date = new Date('2023-05-15T12:00:00Z')
    expect(queryKeyHashFn(['timestamp', date])).toBe(`["timestamp","${date.toISOString()}"]`)

    // Test with Error objects
    const error = new Error('Test error')
    expect(queryKeyHashFn(['error', error])).toMatch(/\["error",\{.*\}\]/)

    // Test with undefined values (these get removed in standard JSON serialization)
    const withUndefined = {a: 1, b: undefined}
    expect(queryKeyHashFn(['test', withUndefined])).toBe('["test",{"a":1}]')

    // Test with object containing Symbol keys - these should be ignored
    const sym = Symbol('test')
    const objWithSymbol = {a: 1, [sym]: 'symbol value'}
    expect(queryKeyHashFn(['test', objWithSymbol])).toBe('["test",{"a":1}]')
  })

  it('should handle edge cases', () => {
    // Empty objects and arrays
    expect(queryKeyHashFn([{}])).toBe('[{}]')
    expect(queryKeyHashFn([[]])).toBe('[[]]')

    // Functions should be ignored in serialization
    const objWithFunction = {
      id: 123,
      getName() {
        return 'Test'
      },
    }
    expect(queryKeyHashFn(['user', objWithFunction])).toBe('["user",{"id":123}]')

    // Mixing undefined in arrays
    expect(queryKeyHashFn(['test', [1, undefined, 3]])).toBe('["test",[1,null,3]]')

    // Test with BigInt - should be handled like any other value
    expect(queryKeyHashFn(['test', BigInt(123)])).toBe('["test","$bigint:123"]')
  })

  it('should handle Set, Map, WeakMap and WeakSet objects', () => {
    // Test with Set
    const set1 = new Set(['c', 'b', 'a'])
    const set2 = new Set(['a', 'b', 'c'])

    // Sets should be sorted for consistent hashing
    expect(queryKeyHashFn(['collection', set1])).toBe(queryKeyHashFn(['collection', set2]))
    expect(queryKeyHashFn(['collection', set1])).toContain('["collection",["a","b","c"]]')

    // Test with Map
    const map1 = new Map([
      ['b', 2],
      ['a', 1],
    ])
    const map2 = new Map([
      ['a', 1],
      ['b', 2],
    ])

    // Maps should be converted to objects with sorted keys
    expect(queryKeyHashFn(['collection', map1])).toBe(queryKeyHashFn(['collection', map2]))
    expect(queryKeyHashFn(['collection', map1])).toBe('["collection",{"a":1,"b":2}]')
  })
})
