import {memo} from 'react'
import type {ColumnInstance} from 'react-table'

import styles from './column-drop-zone-sash.module.css'
import type {TableDataType} from './table-data-type'
import {useTableOverColumn} from './table-provider'

type Props = {
  visibleColumns: Array<ColumnInstance<TableDataType>>
  sticky?: boolean
  height?: number
}

const SASH_WIDTH = 3

/**
 * This is the thick vertical line that is rendered to indicate where a column will
 * be placed when dragging-and-dropping.
 */
export const ColumnDropZoneSash: React.FC<Props> = memo(props => {
  const overColumn = useTableOverColumn()
  const column = overColumn?.column
  const isLast = props.visibleColumns.at(-1) === column
  const side = overColumn?.side

  if (column) {
    let left = column.totalLeft

    if (side === 'right') {
      left += column.totalWidth
    }

    if (isLast && side === 'right') {
      // When over the right side of the final column, left-shift the sash
      // back into the viewport so that it's fully visible.
      left -= SASH_WIDTH
    } else {
      // When over any other column, left-shift the sash by enough pixels
      // so that it is center-aligned with the column dividers.
      left -= Math.ceil(SASH_WIDTH / 2)
    }

    if (props.sticky && props.height) {
      return (
        <div
          style={{
            marginLeft: left,
            marginTop: -props.height,
            height: props.height,
            width: SASH_WIDTH,
          }}
          className={styles.Box}
        />
      )
    }

    return (
      <div
        style={{
          left,
          width: SASH_WIDTH,
        }}
        className={styles.Box_1}
      />
    )
  }

  return null
})

ColumnDropZoneSash.displayName = 'ColumnDropZoneSash'
