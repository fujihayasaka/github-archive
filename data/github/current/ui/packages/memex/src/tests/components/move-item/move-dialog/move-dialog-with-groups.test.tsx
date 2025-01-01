import {render, screen} from '@testing-library/react'
import type {Row} from 'react-table'

import {MemexColumnDataType} from '../../../../client/api/columns/contracts/memex-column'
import {MoveDialog} from '../../../../client/components/move-item/move-dialog/move-dialog'
import {createMemexItemModel, type MemexItemModel} from '../../../../client/models/memex-item-model'
import {buildItemRows} from '../../react-table/table-test-helper'

const setOpen = jest.fn()
const handleDrop = jest.fn()
const items = buildItemRows(6)
const groupId = 'testGroupId'

const rows = items.map((item, index) => ({
  original: createMemexItemModel(item),
  id: index === 0 ? `${groupId}-0` : `${item.id}`,
}))

jest.useFakeTimers()
jest.mock('../../../../client/hooks/use-sorted-by', () => ({
  useSortedBy: () => ({clearSortedBy: jest.fn(), isSorted: false}),
}))

jest.mock('../../../../client/components/react_table/table-provider', () => ({
  useTableInstance: () => ({
    rows,
    groupedRows: [
      {
        id: groupId,
        isGrouped: true,
        groupedSourceObject: {dataType: MemexColumnDataType.IssueType, value: rows[0].original},
        subRows: [rows[0]],
      },
    ],
  }),
}))

jest.mock('../../../../client/components/react_table/row-reordering/hooks/use-row-drop-handler', () => ({
  selectAndFocusItem: jest.fn(),
  useRowDropHandler: () => handleDrop,
}))

describe('MoveDialog with group', () => {
  beforeEach(() => {
    setOpen.mockClear()
    handleDrop.mockClear()
  })

  function renderMoveDialog(index?: number) {
    render(<MoveDialog close={() => setOpen(false)} selectedRow={rows[index ?? 0] as Row<MemexItemModel>} />)
  }

  it('the item name is correctly displayed with a group', async () => {
    renderMoveDialog()

    const item = await screen.findByText(rows[0].original.getRawTitle())
    expect(item).toBeInTheDocument()
  })

  it('dialog title displays correctly with a group name', async () => {
    jest.mock('../../../../client/components/react_table/table-provider', () => ({
      useTableInstance: () => ({
        rows,
        groupedRows: [
          {
            groupedSourceObject: rows[0].original,
            id: groupId,
            isGrouped: true,
            subRows: [rows[0]],
          },
        ],
      }),
    }))

    renderMoveDialog()

    const item = await screen.findByText(rows[0].original.getRawTitle())
    expect(item).toBeInTheDocument()
    const dialogTitle = screen.getByTestId('move-dialog-title')
    expect(dialogTitle).toHaveTextContent('Move selected item within')
  })
})
