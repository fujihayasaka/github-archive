import {DragAndDrop, DragAndDropContext} from '@github-ui/drag-and-drop'
import {noop} from '@github-ui/noop'
import {createContext, useContext, useMemo} from 'react'
import type {Row} from 'react-table'

import {DropSide} from '../../../helpers/dnd-kit/drop-helpers'
import {resolveRawTitleForGroupingContext} from '../../../helpers/table-group-utilities'
import type {MemexItemModel} from '../../../models/memex-item-model'
import {useRowDropHandler} from '../../react_table/row-reordering/hooks/use-row-drop-handler'
import {groupNameFromRow} from '../../react_table/state-providers/table-columns/grouping'
import {useTableInstance} from '../../react_table/table-provider'

export type MoveDialogProps = {
  selectedRow: Row<MemexItemModel>
}

export const MoveDialog = ({close, selectedRow}: MoveDialogProps & {close: () => void}) => {
  const {rows, groupedRows} = useTableInstance()
  const handleDrop = useRowDropHandler()
  const rowObject = selectedRow.original
  const currentRowGroup = getCurrentRowGroup(selectedRow, groupedRows)
  const movableRows = getMovableRows(rows, currentRowGroup, groupedRows)
  const dialogTitle = getDialogTitle(currentRowGroup)

  return (
    <DragAndDropContext.Provider
      value={useMemo(
        () => ({
          dragIndex: null, // This is not used by the MoveDialog, so it can be null
          overId: null, // This is not used by the MoveDialog, so it can be null
          direction: 'vertical', // This is not used by the MoveDialog, so it can be `vertical`
          isInDragMode: false, // This is not used by the MoveDialog, so it can be false
          moveDialogItem: {
            title: rowObject.getRawTitle(),
            index: movableRows.findIndex(row => row.original.id === rowObject.id),
          },
          openMoveDialog: noop, // This is not used by the MoveDialog, so it can be a noop
          moveToPosition: (async (currentPosition: number, newPosition: number, isBefore?: boolean) => {
            const activeItem = movableRows[currentPosition]?.original
            const overItem = movableRows[newPosition]?.original
            if (!activeItem || !overItem) {
              return
            }
            // Close the dialog before the `handleDrop` mutation finishes execution to prevent users from perceiving the operation as slow
            close()
            await handleDrop({
              activeItem,
              overItem,
              side: isBefore ? DropSide.BEFORE : DropSide.AFTER,
            })
          }) as any,
          items: movableRows.map(row => ({
            title: row.original.getRawTitle(),
            id: row.original.id,
          })),
        }),
        [close, movableRows, rowObject, handleDrop],
      )}
    >
      <DragAndDrop.SortableMoveDialog
        dialogTitle={dialogTitle}
        closeDialog={() => {
          close()
        }}
      />
    </DragAndDropContext.Provider>
  )
}

export function getCurrentRowGroup(
  selectedRow: Row<MemexItemModel>,
  groupedRows: Array<Row<MemexItemModel>> | undefined,
): Row<MemexItemModel> | undefined {
  if (!groupedRows) return undefined
  const selectedRowGroupId = groupNameFromRow(selectedRow)
  const selectedRowGroup = groupedRows.find(row => row.id === selectedRowGroupId)
  return selectedRowGroup
}

export function getMovableRows(
  rows: Array<Row<MemexItemModel>>,
  currentRowGroup: Row<MemexItemModel> | undefined,
  groupedRows: Array<Row<MemexItemModel>> | undefined,
): Array<Row<MemexItemModel>> {
  // If there's no/only one row group(s), we can move our item wherever we want
  if (!groupedRows || groupedRows.length < 2) return rows
  // Otherwise, limit it to other rows in the same group
  if (currentRowGroup?.isGrouped) return currentRowGroup.subRows
  return rows
}

function getDialogTitle(currentRowGroup: Row<MemexItemModel> | undefined): string | undefined {
  if (!currentRowGroup) return
  // eslint-disable-next-line i18n-text/no-en
  return `Move selected item within ${resolveRawTitleForGroupingContext(currentRowGroup.groupedSourceObject)}`
}

export type MoveDialogContextProps = {
  setMoveDialogProps: (props: MoveDialogProps | null) => void
}

export const MoveDialogContext = createContext<MoveDialogContextProps>({
  setMoveDialogProps: () => {},
})

export const useMoveDialog = () => {
  const {setMoveDialogProps} = useContext(MoveDialogContext)

  return {setMoveDialogProps}
}
