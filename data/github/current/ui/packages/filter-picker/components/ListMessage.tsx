import type {UseQueryResult} from '@github-ui/react-query'
import type {PropsWithChildren} from 'react'

import type {IPickerItem, ItemLiterals} from '../types'

export function ListMessage({children}: PropsWithChildren) {
  return <div className="m-6 p-6 text-center">{children}</div>
}

export function getBlankMessage(
  {isLoading, isError}: UseQueryResult,
  visibleItems: IPickerItem[],
  {itemsName}: ItemLiterals,
): string {
  if (isLoading) {
    return `Loading ${itemsName}...`
  }

  if (isError) {
    return `Error loading ${itemsName}.`
  }

  if (visibleItems.length === 0) {
    return `No ${itemsName} to show.`
  }

  return ''
}

export function getResultsAnnouncement({
  blankMessage,
  itemsCount,
  totalItemsCount,
  itemLiterals: {itemName, itemsName},
}: {
  blankMessage: string
  itemsCount: number
  totalItemsCount: number
  itemLiterals: ItemLiterals
}) {
  if (blankMessage) {
    return blankMessage
  }
  if (itemsCount >= totalItemsCount) {
    return `${itemsCount} ${itemsCount === 1 ? itemName : itemsName} matching`
  }
  if (itemsCount > 0) {
    return `${totalItemsCount} ${itemsName} matching, showing first ${itemsCount}`
  }
}
