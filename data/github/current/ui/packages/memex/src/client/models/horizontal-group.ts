import type {GroupingMetadataWithSource} from '../features/grouping/types'
import type {GroupId} from '../state-providers/memex-items/queries/query-keys'
import type {Resources} from '../strings'
import type {ColumnModel} from './column-model'
import type {MemexItemModel} from './memex-item-model'

export type ItemDataForVerticalColumn = {
  items: ReadonlyArray<MemexItemModel>
  groupId?: GroupId
  totalCount?: number
}

export type ItemDataForSwimlaneCell = {
  items: ReadonlyArray<MemexItemModel>
  groupId?: GroupId
  hasMoreItems?: boolean
}

export type ItemsGroupedByVerticalColumn = Readonly<{
  [k: string]: ItemDataForVerticalColumn
}>

export type ItemsGroupedBySwimlaneCell = Readonly<{
  [k: string]: ItemDataForSwimlaneCell
}>

type BaseHorizontalGroup = {
  isCollapsed: boolean
  rows: ReadonlyArray<MemexItemModel>
  totalCount: number
}

/**
 * Merging this with value and sourceObject to make it a bit easier to interact with them
 */
export type UngroupedHorizontalGroup = BaseHorizontalGroup & {
  value: typeof Resources.undefined
  sourceObject?: undefined
  itemsByVerticalGroup: ItemsGroupedByVerticalColumn
}

/**
 * We optionally include a `serverGroupId` when the group is dervied from a PWL group provided by the server
 */
export type GroupedHorizontalGroup = GroupingMetadataWithSource &
  BaseHorizontalGroup & {itemsByVerticalGroup: ItemsGroupedBySwimlaneCell; serverGroupId?: string}
export type HorizontalGroup = GroupedHorizontalGroup | UngroupedHorizontalGroup

export type HorizontalGrouping =
  | {
      isHorizontalGrouped: true
      horizontalGroupedByColumn: ColumnModel
      allItemsByVerticalGroup: ItemsGroupedByVerticalColumn
      horizontalGroups: ReadonlyArray<Readonly<GroupedHorizontalGroup>>
    }
  | {
      isHorizontalGrouped: false
      allItemsByVerticalGroup: ItemsGroupedByVerticalColumn
      horizontalGroups: [Readonly<UngroupedHorizontalGroup>]
    }

export function hasServerGroupId(
  horizontalGroup: HorizontalGroup | undefined,
): horizontalGroup is GroupedHorizontalGroup {
  return horizontalGroup != null && 'serverGroupId' in horizontalGroup
}
