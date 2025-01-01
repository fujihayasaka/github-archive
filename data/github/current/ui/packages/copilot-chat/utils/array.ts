/**
 * Split an array into groups based on unique values returned by the differentiator.
 * @example
 * // Split numbers into even and odd
 * const groups = partition([1,2,3,4,5], n => n % 2)
 * const evens = groups.get(0) ?? []
 * const odds = groups.get(1) ?? []
 */
export function group<T, K extends string | number | symbol>(array: T[], differentiator: (el: T) => K) {
  const result: Partial<Record<K, T[]>> = {}
  for (const el of array) {
    const key = differentiator(el)
    result[key] ??= []
    result[key].push(el)
  }
  return result
}
