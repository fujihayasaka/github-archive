import {isItemMovingWithinSortedValue} from '../../../client/features/sorting/is-item-moving-within-sorted-value'
import {createColumnModel} from '../../../client/models/column-model'
import type {MemexItemModel} from '../../../client/models/memex-item-model'
import {columnValueFactory} from '../../factories/column-values/column-value-factory'
import {customColumnFactory} from '../../factories/columns/custom-column-factory'
import {issueFactory} from '../../factories/memex-items/issue-factory'
import {createMemexItemModel} from '../../mocks/models/memex-item-model'

describe('isItemMovingWithinSortedValue', () => {
  it('returns true if only a single item', () => {
    const {sortField, itemsInGroup} = createItemsWithValue([{value: 'aaa', count: 1}])
    const itemToMove = itemsInGroup[0]
    const overItemId = itemToMove.id
    const result = isItemMovingWithinSortedValue(itemToMove, sortField, itemsInGroup, overItemId, 'before')
    expect(result).toBeTruthy()
  })

  it('returns false if two items with different values and moving down', () => {
    const {sortField, itemsInGroup} = createItemsWithValue([
      {value: 'aaa', count: 1},
      {value: 'bbb', count: 1},
    ])
    const itemToMove = itemsInGroup[0]
    const overItemId = itemsInGroup[1].id
    const result = isItemMovingWithinSortedValue(itemToMove, sortField, itemsInGroup, overItemId, 'after')
    expect(result).toBeFalsy()
  })

  it('returns false if two items with different values and moving up', () => {
    const {sortField, itemsInGroup} = createItemsWithValue([
      {value: 'aaa', count: 1},
      {value: 'bbb', count: 1},
    ])
    const itemToMove = itemsInGroup[1]
    const overItemId = itemsInGroup[0].id
    const result = isItemMovingWithinSortedValue(itemToMove, sortField, itemsInGroup, overItemId, 'before')
    expect(result).toBeFalsy()
  })

  it('returns true if moved down to boundary between values', () => {
    const {sortField, itemsInGroup} = createItemsWithValue([
      {value: 'aaa', count: 2},
      {value: 'bbb', count: 1},
    ])
    const itemToMove = itemsInGroup[0]
    const overItemId = itemsInGroup[2].id
    const result = isItemMovingWithinSortedValue(itemToMove, sortField, itemsInGroup, overItemId, 'before')
    expect(result).toBeTruthy()
  })

  it('returns false if moved down to after last item when in a different group', () => {
    const {sortField, itemsInGroup} = createItemsWithValue([
      {value: 'aaa', count: 2},
      {value: 'bbb', count: 1},
    ])
    const itemToMove = itemsInGroup[0]
    const overItemId = itemsInGroup[2].id
    const result = isItemMovingWithinSortedValue(itemToMove, sortField, itemsInGroup, overItemId, 'after')
    expect(result).toBeFalsy()
  })

  it('returns true if moved up to boundary between values with before', () => {
    const {sortField, itemsInGroup} = createItemsWithValue([
      {value: 'aaa', count: 1},
      {value: 'bbb', count: 2},
    ])
    const itemToMove = itemsInGroup[2]
    const overItemId = itemsInGroup[1].id
    const result = isItemMovingWithinSortedValue(itemToMove, sortField, itemsInGroup, overItemId, 'before')
    expect(result).toBeTruthy()
  })

  it('returns true if moved up to boundary between values with after', () => {
    const {sortField, itemsInGroup} = createItemsWithValue([
      {value: 'aaa', count: 1},
      {value: 'bbb', count: 2},
    ])
    const itemToMove = itemsInGroup[2]
    const overItemId = itemsInGroup[0].id
    const result = isItemMovingWithinSortedValue(itemToMove, sortField, itemsInGroup, overItemId, 'after')
    expect(result).toBeTruthy()
  })

  it('returns false if moved up to before first value when in a different group', () => {
    const {sortField, itemsInGroup} = createItemsWithValue([
      {value: 'aaa', count: 1},
      {value: 'bbb', count: 2},
    ])
    const itemToMove = itemsInGroup[2]
    const overItemId = itemsInGroup[0].id
    const result = isItemMovingWithinSortedValue(itemToMove, sortField, itemsInGroup, overItemId, 'before')
    expect(result).toBeFalsy()
  })
})

function createItemsWithValue(itemCountsForValue: Array<{value: string; count: number}>) {
  const sortField = createColumnModel(customColumnFactory.build({dataType: 'text', name: 'Sort Field'}))
  const itemsInGroup: Array<MemexItemModel> = []
  for (const itemCounts of itemCountsForValue) {
    for (let i = 0; i < itemCounts.count; i++) {
      const item = issueFactory.build({
        memexProjectColumnValues: [columnValueFactory.text(itemCounts.value, sortField.name, [sortField]).build()],
      })
      itemsInGroup.push(createMemexItemModel(item))
    }
  }
  return {sortField, itemsInGroup}
}
