import type {MemexColumn, SystemColumnId} from './memex-column'
import type {CustomColumnKind, CustomColumnMap, SystemColumnMap} from './storage'
import type {DenormalizedTitleValue, TitleValueBase} from './title'

export interface ItemWithColumnData<TColumnValue> {
  memexProjectItemId: number
  value: TColumnValue
}

type ValueForSystemColumn<ID extends SystemColumnId> = NonNullable<SystemColumnMap[ID]['value']>

type SystemColumnWithItems<ID extends SystemColumnId> = MemexColumn & {
  id: ID
  memexProjectColumnValues?: Array<ItemWithColumnData<ValueForSystemColumn<ID>>>
}

type CustomColumnWithItems<T extends CustomColumnKind> = MemexColumn & {
  id: number
  memexProjectColumnValues?: Array<ItemWithColumnData<CustomColumnMap[T]['value']>>
}

// Title value is special, because `contentType` is applied in client code, separate from the API response.
type TitleColumnWithItems = MemexColumn & {
  id: typeof SystemColumnId.Title
  memexProjectColumnValues?: Array<ItemWithColumnData<TitleValueBase | DenormalizedTitleValue>>
}

type NonTitleSystemColumnIds = Exclude<SystemColumnId, typeof SystemColumnId.Title>

type SystemColumnWithWithItems = TitleColumnWithItems | SystemColumnWithItems<NonTitleSystemColumnIds>

type CustomColumnsWithItems = CustomColumnWithItems<keyof CustomColumnMap>

export type IColumnWithItems = SystemColumnWithWithItems | CustomColumnsWithItems
