import {isGroupableColumn} from '../../models/column-capabilities'
import type {ColumnModel} from '../../models/column-model'
import type {VerticalGroup} from '../../models/vertical-group'

export function normalizeGroupName(group: VerticalGroup) {
  return group.name.toLocaleLowerCase().trim()
}

export function isValidHorizontalGroupByColumn(column: ColumnModel): boolean {
  return isGroupableColumn(column.dataType)
}
