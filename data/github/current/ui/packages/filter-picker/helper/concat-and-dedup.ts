import type {IPickerItem} from '../types'

const MAX_VISIBLE_SELECTED_ITEMS = 500
export const PAGE_SIZE = 100

/** Concat A and B but showing always all A items and only the first B items to complete a page */
export function concatAndDedup<T extends IPickerItem>(a: T[], b: T[]): T[] {
  if (a.length >= PAGE_SIZE) {
    return a.slice(0, MAX_VISIBLE_SELECTED_ITEMS)
  }

  const aIds = new Set(a.map(item => item.id))
  const dedupedB = b.filter(item => !aIds.has(item.id))
  return a.concat(dedupedB).slice(0, PAGE_SIZE)
}
