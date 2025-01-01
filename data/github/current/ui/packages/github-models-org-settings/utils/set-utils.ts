/**
 * Replicating https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Set/difference
 * while that Set function is still too new to be available in Storybook tests.
 */
export function setDifference<T>(set1: Set<T>, set2: Set<T>): Set<T> {
  const result = new Set(set1)
  for (const value of set2) {
    result.delete(value)
  }
  return result
}

/**
 * Replicating https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Set/isSubsetOf
 * while that Set function is still too new to be available in Storybook tests.
 */
export function isSubsetOf<T>(set1: Set<T>, set2: Set<T>): boolean {
  for (const value of set2) {
    if (!set1.has(value)) return false
  }
  return true
}

/**
 * Replicating https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Set/isDisjointFrom
 * while that Set function is still too new to be available in Storybook tests.
 */
export function areSetsDisjoint<T>(set1: Set<T>, set2: Set<T>): boolean {
  for (const value of set1) {
    if (set2.has(value)) return false
  }
  return true
}
