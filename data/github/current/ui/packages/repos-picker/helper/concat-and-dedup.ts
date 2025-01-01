import type {PickerRepository} from '../types'

const MAX_VISIBLE_SELECTED_ITEMS = 500
export const PAGE_SIZE = 100

/** Concat A and B but showing always all A items and only the first B items to complete a page */
export function concatAndDedup(a: PickerRepository[], b: PickerRepository[]) {
  if (a.length >= PAGE_SIZE) {
    return a.slice(0, MAX_VISIBLE_SELECTED_ITEMS)
  }

  const aIds = new Set(a.map(repo => repo.id))
  const dedupedB = b.filter(repo => !aIds.has(repo.id))
  return a.concat(dedupedB).slice(0, PAGE_SIZE)
}
