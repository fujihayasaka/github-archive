import {DragAndDropMoveOptions} from '@github-ui/drag-and-drop'
import {render, screen} from '@testing-library/react'
import type {Row} from 'react-table'

import {MoveDialog} from '../../../../client/components/move-item/move-dialog/move-dialog'
import {DropSide} from '../../../../client/helpers/dnd-kit/drop-helpers'
import {createMemexItemModel, type MemexItemModel} from '../../../../client/models/memex-item-model'
import {buildRows} from '../../react-table/table-test-helper'
import {selectAfter, selectBefore, selectMoveAction, submitDialog} from '../utils'

const setOpen = jest.fn()
const handleDrop = jest.fn()
const items = buildRows(6)

const rows = items.map(item => ({
  original: createMemexItemModel(item),
}))

jest.useFakeTimers()
jest.mock('../../../../client/hooks/use-sorted-by', () => ({
  useSortedBy: () => ({clearSortedBy: jest.fn(), isSorted: false}),
}))

jest.mock('../../../../client/components/react_table/table-provider', () => ({
  useTableInstance: () => ({rows}),
}))

jest.mock('../../../../client/components/react_table/row-reordering/hooks/use-row-drop-handler', () => ({
  selectAndFocusItem: jest.fn(),
  useRowDropHandler: () => handleDrop,
}))

describe('MoveDialog', () => {
  beforeEach(() => {
    setOpen.mockClear()
    handleDrop.mockClear()
  })

  function renderMoveDialog(index?: number) {
    render(<MoveDialog close={() => setOpen(false)} selectedRow={rows[index ?? 0] as Row<MemexItemModel>} />)
  }

  it('the item name is correctly displayed', async () => {
    renderMoveDialog()

    const item = await screen.findByText(rows[0].original.getRawTitle())
    expect(item).toBeInTheDocument()
  })

  it('dialog title displays correctly without a group name', async () => {
    renderMoveDialog()

    const item = await screen.findByText(rows[0].original.getRawTitle())
    expect(item).toBeInTheDocument()
    const dialogTitle = screen.getByTestId('move-dialog-title')
    expect(dialogTitle).toHaveTextContent('Move selected item')
    expect(dialogTitle).not.toHaveTextContent('Move selected item within')
  })

  it('the correct move before items shows up in the moveDialog when moving the first item', async () => {
    renderMoveDialog()
    await selectMoveAction(DragAndDropMoveOptions.BEFORE)

    const options = screen.getAllByRole('option')
    const allBeforeOptions = options
      .filter(option => option.textContent?.startsWith('Cell'))
      .map(option => option.textContent)

    expect(allBeforeOptions).not.toContain('Cell 1')
    expect(allBeforeOptions).not.toContain('Cell 2')
    expect(allBeforeOptions).toContain('Cell 3')
    expect(allBeforeOptions).toContain('Cell 4')
    expect(allBeforeOptions).toContain('Cell 5')
    expect(allBeforeOptions).toContain('Cell 6')
  })

  it('the correct move after items shows up in the moveDialog when moving the first item', async () => {
    renderMoveDialog()
    await selectMoveAction(DragAndDropMoveOptions.AFTER)
    const options = screen.getAllByRole('option')
    const allBeforeOptions = options
      .filter(option => option.textContent?.startsWith('Cell'))
      .map(option => option.textContent)

    expect(allBeforeOptions).not.toContain('Cell 1')
    expect(allBeforeOptions).toContain('Cell 2')
    expect(allBeforeOptions).toContain('Cell 3')
    expect(allBeforeOptions).toContain('Cell 4')
    expect(allBeforeOptions).toContain('Cell 5')
    expect(allBeforeOptions).toContain('Cell 6')
  })

  it('the correct move before items shows up in the moveDialog when moving the last item', async () => {
    renderMoveDialog(5)
    await selectMoveAction(DragAndDropMoveOptions.BEFORE)

    const options = screen.getAllByRole('option')
    const allBeforeOptions = options
      .filter(option => option.textContent?.startsWith('Cell'))
      .map(option => option.textContent)

    expect(allBeforeOptions).toContain('Cell 1')
    expect(allBeforeOptions).toContain('Cell 2')
    expect(allBeforeOptions).toContain('Cell 3')
    expect(allBeforeOptions).toContain('Cell 4')
    expect(allBeforeOptions).toContain('Cell 5')
    expect(allBeforeOptions).not.toContain('Cell 6')
  })

  it('the correct move after items shows up in the moveDialog when moving the last item', async () => {
    renderMoveDialog(5)
    await selectMoveAction(DragAndDropMoveOptions.AFTER)
    const options = screen.getAllByRole('option')
    const allBeforeOptions = options
      .filter(option => option.textContent?.startsWith('Cell'))
      .map(option => option.textContent)

    expect(allBeforeOptions).toContain('Cell 1')
    expect(allBeforeOptions).toContain('Cell 2')
    expect(allBeforeOptions).toContain('Cell 3')
    expect(allBeforeOptions).toContain('Cell 4')
    expect(allBeforeOptions).not.toContain('Cell 5')
    expect(allBeforeOptions).not.toContain('Cell 6')
  })

  it('the correct move before items shows up in the moveDialog when moving the middle item', async () => {
    renderMoveDialog(1)
    await selectMoveAction(DragAndDropMoveOptions.BEFORE)

    const options = screen.getAllByRole('option')
    const allBeforeOptions = options
      .filter(option => option.textContent?.startsWith('Cell'))
      .map(option => option.textContent)

    expect(allBeforeOptions).toContain('Cell 1')
    expect(allBeforeOptions).not.toContain('Cell 2')
    expect(allBeforeOptions).not.toContain('Cell 3')
    expect(allBeforeOptions).toContain('Cell 4')
    expect(allBeforeOptions).toContain('Cell 5')
    expect(allBeforeOptions).toContain('Cell 6')
  })

  it('the correct move after items shows up in the moveDialog when moving the middle item', async () => {
    renderMoveDialog(1)
    await selectMoveAction(DragAndDropMoveOptions.AFTER)
    const options = screen.getAllByRole('option')
    const allBeforeOptions = options
      .filter(option => option.textContent?.startsWith('Cell'))
      .map(option => option.textContent)

    expect(allBeforeOptions).not.toContain('Cell 1')
    expect(allBeforeOptions).not.toContain('Cell 2')
    expect(allBeforeOptions).toContain('Cell 3')
    expect(allBeforeOptions).toContain('Cell 4')
    expect(allBeforeOptions).toContain('Cell 5')
    expect(allBeforeOptions).toContain('Cell 6')
  })

  it('handleDrop is called with correct indices when moving in the middle', async () => {
    renderMoveDialog(1)
    await selectMoveAction(DragAndDropMoveOptions.AFTER)

    await selectAfter('Cell 4')
    await submitDialog()

    expect(handleDrop).toHaveBeenCalledWith({
      activeItem: rows[1].original,
      overItem: rows[3].original,
      side: DropSide.AFTER,
    })
  })

  it('handleDrop is called with correct indices when moving the first item', async () => {
    renderMoveDialog(0)
    await selectMoveAction(DragAndDropMoveOptions.AFTER)

    await selectAfter('Cell 5')
    await submitDialog()

    expect(handleDrop).toHaveBeenCalledWith({
      activeItem: rows[0].original,
      overItem: rows[4].original,
      side: DropSide.AFTER,
    })
  })

  it('handleDrop is called with correct indices when moving the last item', async () => {
    renderMoveDialog(5)
    await selectMoveAction(DragAndDropMoveOptions.BEFORE)

    await selectBefore('Cell 3')
    await submitDialog()

    expect(handleDrop).toHaveBeenCalledWith({
      activeItem: rows[5].original,
      overItem: rows[2].original,
      side: DropSide.BEFORE,
    })
  })
})
