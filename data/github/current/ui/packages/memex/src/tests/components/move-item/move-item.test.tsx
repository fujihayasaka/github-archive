import {act, render, screen} from '@testing-library/react'
import {useState} from 'react'
import type {Row} from 'react-table'

import {
  MoveDialog,
  MoveDialogContext,
  type MoveDialogProps,
} from '../../../client/components/move-item/move-dialog/move-dialog'
import {MoveItem} from '../../../client/components/move-item/move-item'
import {createMemexItemModel, type MemexItemModel} from '../../../client/models/memex-item-model'
import {buildRows} from '../react-table/table-test-helper'

const handleDrop = jest.fn()
const items = buildRows(6)

const rows = items.map(item => ({
  original: createMemexItemModel(item),
}))

jest.mock('../../../client/hooks/use-sorted-by', () => ({
  useSortedBy: () => ({clearSortedBy: jest.fn(), isSorted: false}),
}))

jest.mock('../../../client/components/react_table/table-provider', () => ({
  useTableInstance: () => ({rows}),
}))

jest.mock('../../../client/components/react_table/row-reordering/hooks/use-row-drop-handler', () => ({
  selectAndFocusItem: jest.fn(),
  useRowDropHandler: () => handleDrop,
}))

const memexItemRow = rows[2] as Row<MemexItemModel>

const TestWrapper = () => {
  const [moveDialogProps, setMoveDialogProps] = useState<MoveDialogProps | null>(null)

  return (
    <MoveDialogContext.Provider
      value={{
        setMoveDialogProps: (props: MoveDialogProps | null) => {
          setMoveDialogProps(props)
        },
      }}
    >
      {moveDialogProps && (
        <MoveDialog
          {...moveDialogProps}
          close={() => {
            act(() => setMoveDialogProps(null))
          }}
        />
      )}
      <MoveItem selectedRow={memexItemRow} />
    </MoveDialogContext.Provider>
  )
}

describe('MoveItem', () => {
  function renderMoveItem() {
    render(<TestWrapper />)
  }

  it('the advanced move button is listed', async () => {
    renderMoveItem()
    const trigger = await screen.findByRole('listitem')
    expect(trigger).toHaveTextContent(`Move item`)
  })

  it('when the advance move button is pressed the MoveDialog opens', async () => {
    renderMoveItem()
    const trigger = await screen.findByRole('listitem')
    act(() => {
      trigger.click()
    })
    const moveDialog = await screen.findByTestId('move-dialog-form')
    expect(moveDialog).toBeInTheDocument()
  })
})
