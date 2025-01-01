/**
 * Creates an array of unique values from the provided array based on a key function.
 * Duplicate items are determined by the return value of the key function.
 * When duplicates are found, the last item with the same key is kept.
 *
 * @param array - The array to filter for unique values.
 * @param fn - A function that returns a key for each item in the array.
 * @returns An array of unique items based on the provided key function.
 */
export function uniqueBy<T, K extends string | number | symbol>(array: T[], fn: (item: T) => K): T[] {
  const mapByUniqueKey = array.reduce<Record<K, T>>(
    (acc, item) => {
      const key = fn(item)

      return {...acc, [key]: item}
    },
    {} as Record<K, T>,
  )

  return Object.values(mapByUniqueKey)
}
