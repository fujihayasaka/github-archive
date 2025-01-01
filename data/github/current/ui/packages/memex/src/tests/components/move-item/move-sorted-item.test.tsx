import {act, render, screen} from '@testing-library/react'
import type {Row} from 'react-table'

import {MoveItem} from '../../../client/components/move-item/move-item'
import {createMemexItemModel, type MemexItemModel} from '../../../client/models/memex-item-model'
import {buildRows} from '../react-table/table-test-helper'

const handleDrop = jest.fn()
const items = buildRows(6)

const rows = items.map(item => ({
  original: createMemexItemModel(item),
}))

const removeSortOrder = jest.fn()

jest.mock('../../../client/hooks/use-sorted-by', () => ({
  useSortedBy: () => ({clearSortedBy: removeSortOrder, isSorted: true}),
}))
jest.mock('../../../client/components/react_table/table-provider', () => ({
  useTableInstance: () => ({rows}),
}))

jest.mock('../../../client/components/react_table/row-reordering/hooks/use-row-drop-handler', () => ({
  selectAndFocusItem: jest.fn(),
  useRowDropHandler: () => handleDrop,
}))

describe('MoveItem', () => {
  beforeEach(() => {
    removeSortOrder.mockClear()
  })

  function renderMoveItem() {
    const memexItemRow = rows[2] as Row<MemexItemModel>

    render(<MoveItem selectedRow={memexItemRow} />)
  }

  it('if items are sorted the remove sort confirmation dialog is displayed', async () => {
    renderMoveItem()
    const trigger = await screen.findByRole('listitem')
    act(() => {
      trigger.click()
    })
    const heading = await screen.findByRole('heading')
    expect(heading).toHaveTextContent('Confirm sort order overwrite')
  })

  it('sort order is removed when a user presses overwrite sorting', async () => {
    renderMoveItem()
    const trigger = await screen.findByRole('listitem')
    act(() => {
      trigger.click()
    })

    expect(removeSortOrder).not.toHaveBeenCalled()
    const confirmButton = await screen.findByRole('button', {name: 'Overwrite sorting'})
    act(() => {
      confirmButton.click()
    })
    // clear all promises
    const flushPromises = () => new Promise(setImmediate)
    await flushPromises()
    expect(removeSortOrder).toHaveBeenCalled()
  })

  it('sort order is not removed when a user presses cancel', async () => {
    renderMoveItem()
    const trigger = await screen.findByRole('listitem')
    act(() => {
      trigger.click()
    })

    expect(removeSortOrder).not.toHaveBeenCalled()
    const confirmButton = await screen.findByRole('button', {name: 'Cancel'})
    act(() => {
      confirmButton.click()
    })
    const flushPromises = () => new Promise(setImmediate)
    await flushPromises()
    expect(removeSortOrder).not.toHaveBeenCalled()
  })
})
