import {useDndContext} from '@github-ui/drag-and-drop'
import {PlusIcon} from '@primer/octicons-react'
import {Octicon} from '@primer/react/deprecated'
import {useCallback, useMemo} from 'react'
import type {Row} from 'react-table'

import {DropSide, getVerticalDropSide} from '../../../helpers/dnd-kit/drop-helpers'
import {useKeyPress} from '../../../state-providers/keypress/key-press-provider'
import type {TableDataType} from '../table-data-type'
import {ROW_DRAG_HANDLE_WIDTH} from '../use-row-drag-handle'
import {getSashPosition} from './helpers/drop-helpers'
import {ReorderableRowData} from './reorderable-rows'
// eslint-disable-next-line primer-react/enforce-css-module-default-import
import styles0 from './row-reorder-sash.module.css'

type RowReorderSashProps = {
  rows: Array<Row<TableDataType>>
  isGrouped: boolean
  /** Scrolling container for table rows */
  scrollRef: React.MutableRefObject<HTMLDivElement | null>
  /** Header height used to offset the sash position within the scrolling container. */
  headerHeight?: number
  /** Restrict the sash width to a specific width. Used in roadmap view. */
  tableWidth?: number
}

const SASH_HEIGHT = 3
const SASH_ICON_SIZE = 16
const ROW_BORDER_OFFSET = 1

export const RowReorderSash: React.FC<RowReorderSashProps> = ({
  rows,
  isGrouped,
  scrollRef,
  headerHeight,
  tableWidth,
}) => {
  const {active, over} = useDndContext()
  const {ctrlKey} = useKeyPress()

  const lastOfTypeIndexes = useMemo(() => {
    const last: Array<number> = []
    if (isGrouped) {
      for (const row of rows) {
        const lastId = row.subRows[row.subRows.length - 1]?.original?.id
        if (lastId !== undefined) last.push(lastId)
      }
    } else {
      const lastId = rows[rows.length - 1]?.original?.id
      if (lastId !== undefined) last.push(lastId)
    }
    return last
  }, [rows, isGrouped])

  const isLastOfType = useCallback((overItemId: number) => lastOfTypeIndexes.includes(overItemId), [lastOfTypeIndexes])

  const side = active ? getVerticalDropSide(active, over) : null
  const dropY = side ? getSashPosition(over, side) : null
  const overData = over?.data.current
  const overId = ReorderableRowData.is(overData) ? overData.originalItemId : null
  const lastOfType = overId ? isLastOfType(overId) : false
  const lastOfTypeOffset = side === DropSide.AFTER && lastOfType ? -1 * SASH_HEIGHT + ROW_BORDER_OFFSET : 0

  const styles = useMemo(() => {
    if (scrollRef?.current && dropY !== null) {
      const rect = scrollRef.current.getBoundingClientRect()
      const headerOffset = headerHeight ?? 0
      const width = tableWidth ? `${tableWidth}px` : '100%'

      return {
        top: scrollRef.current.scrollTop - rect.top - headerOffset + lastOfTypeOffset + dropY - ROW_BORDER_OFFSET,
        left: scrollRef.current.scrollLeft,
        width,
      }
    }
    return {}
  }, [scrollRef, tableWidth, headerHeight, dropY, lastOfTypeOffset])

  return (
    <>
      {Boolean(active && over && dropY !== null && overId && side && active.id !== over.id) && (
        <div
          style={{
            height: SASH_HEIGHT,
            ...styles,
          }}
          className={styles0.Box}
        >
          {isGrouped && ctrlKey ? (
            <Octicon
              icon={PlusIcon}
              sx={{
                left: ROW_DRAG_HANDLE_WIDTH - SASH_ICON_SIZE / 2,
                top: `-7px`,
              }}
              size={SASH_ICON_SIZE}
              className={styles0.Octicon}
            />
          ) : null}
        </div>
      )}
    </>
  )
}
