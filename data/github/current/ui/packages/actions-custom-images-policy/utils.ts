/*
 * Split a list into two lists based on a predicate.
 */
export function partition<T>(list: T[], predicate: (item: T) => boolean): [T[], T[]] {
  const match: T[] = []
  const noMatch: T[] = []
  return list.reduce(
    (acc, item) => {
      acc[predicate(item) ? 0 : 1].push(item)
      return acc
    },
    [match, noMatch],
  )
}
