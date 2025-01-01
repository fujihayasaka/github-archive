import type {QueryKey} from '@tanstack/react-query'
/**
 * Default query & mutation keys hash function.
 * Hashes the value into a stable hash.
 *
 * Extended from https://github.com/TanStack/query/blob/256624af671772732c7e11c2689bb1697ee7e72c/packages/query-core/src/utils.ts#L212-L223
 */
export function queryKeyHashFn(queryKey: QueryKey): string {
  return JSON.stringify(queryKey, (_, val) => {
    if (isPlainObject(val)) {
      return Object.keys(val)
        .sort()
        .reduce((result, key) => {
          result[key] = val[key]
          return result
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
        }, {} as any)
    }

    // #region Special Type Handling
    /**
     * Define extensions to the standard JSONSerializer here
     * This is used to ensure that the query key is always the same for the same data
     * Especially when that data doesn't traditionally `JSON.stringify` correctly.
     */

    // stringify the URLSearchParams object to ensure consistent hashing. Otherwsie JSON.stringify would make it `"{}"`
    if (val instanceof URLSearchParams) {
      return new URLSearchParams([...val.entries()].sort(([a], [b]) => a.localeCompare(b))).toString()
    }
    if (typeof val === 'bigint') {
      // BigInt is not supported by JSON.stringify, so we convert it to a string
      return `$bigint:${val}`
    }
    if (val instanceof Set) {
      // Convert Set to a sorted array for more consistent JSON serialization
      return Array.from(val).sort()
    }
    if (val instanceof Map) {
      // Convert Map to a standard object with sorted keys for consistent serialization
      return Array.from(val.entries())
        .sort(([a], [b]) => a.localeCompare(b))
        .reduce(
          (obj, [key, value]) => {
            obj[key] = value
            return obj
          },
          {} as Record<string, unknown>,
        )
    }

    // #endregion Special Type Handling

    return val
  })
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function hasObjectPrototype(o: any): boolean {
  return Object.prototype.toString.call(o) === '[object Object]'
}
// Copied from: https://github.com/jonschlinkert/is-plain-object
// eslint-disable-next-line @typescript-eslint/no-wrapper-object-types, @typescript-eslint/no-explicit-any
function isPlainObject(o: any): o is Object {
  if (!hasObjectPrototype(o)) {
    return false
  }

  // If has no constructor
  const ctor = o.constructor
  if (ctor === undefined) {
    return true
  }

  // If has modified prototype
  const prot = ctor.prototype
  if (!hasObjectPrototype(prot)) {
    return false
  }

  // If constructor does not have an Object-specific method
  if (!prot.hasOwnProperty('isPrototypeOf')) {
    return false
  }

  // Handles Objects created by Object.create(<arbitrary prototype>)
  if (Object.getPrototypeOf(o) !== Object.prototype) {
    return false
  }

  // Most likely a plain Object
  return true
}
