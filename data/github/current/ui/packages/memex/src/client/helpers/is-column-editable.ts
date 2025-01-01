import {SystemColumnId} from '../api/columns/contracts/memex-column'
import type {ColumnModel} from '../models/column-model'

const editableColumnTypes = new Set<SystemColumnId>([SystemColumnId.Status, SystemColumnId.SubIssuesProgress])

/**
 * Given a column, returns true if the column is editable by some user
 * and false if it is not.
 *
 * A column is editable if a user defined it _or_ if it's the Status Column,
 * which is _not_ `userDefined` but is editable.
 */
export function isColumnUserEditable(column: ColumnModel) {
  return column.userDefined || editableColumnTypes.has(column.id)
}
