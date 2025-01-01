import {renderHook, act} from '@testing-library/react'
import {useCheckboxSelection} from '../use-checkbox-selection'

describe('useCheckboxSelection', () => {
  const items = [
    {id: 1, login: 'Item 1'},
    {id: 2, login: 'Item 2'},
    {id: 3, login: 'Item 3'},
  ]

  const getItemId = (item: {id: number; login: string}) => item.id

  test('initializes with no items selected', () => {
    const {result} = renderHook(() => useCheckboxSelection(items, getItemId))

    expect(result.current.selectedItems.size).toBe(0)
    expect(result.current.selectAll).toBe(false)
  })

  test('selects an individual item', () => {
    const {result} = renderHook(() => useCheckboxSelection(items, getItemId))

    act(() => {
      result.current.handleSelectItem(1)
    })

    expect(result.current.selectedItems.has(1)).toBe(true)
    expect(result.current.selectAll).toBe(false)
  })

  test('deselects an individual item', () => {
    const {result} = renderHook(() => useCheckboxSelection(items, getItemId))

    act(() => {
      result.current.handleSelectItem(1)
    })

    expect(result.current.selectedItems.has(1)).toBe(true)

    act(() => {
      result.current.handleSelectItem(1)
    })

    expect(result.current.selectedItems.has(1)).toBe(false)
  })

  test('selects all items when "select all" is triggered', () => {
    const {result} = renderHook(() => useCheckboxSelection(items, getItemId))

    act(() => {
      result.current.handleSelectAll()
    })

    expect(result.current.selectedItems.size).toBe(items.length)
    expect(result.current.selectAll).toBe(true)
  })

  test('deselects all items when "select all" is toggled off', () => {
    const {result} = renderHook(() => useCheckboxSelection(items, getItemId))

    act(() => {
      result.current.handleSelectAll()
    })

    expect(result.current.selectedItems.size).toBe(items.length)

    act(() => {
      result.current.handleSelectAll()
    })

    expect(result.current.selectedItems.size).toBe(0)
    expect(result.current.selectAll).toBe(false)
  })

  test('handles mixed selection states correctly', () => {
    const {result} = renderHook(() => useCheckboxSelection(items, getItemId))

    // Select one item
    act(() => {
      result.current.handleSelectItem(1)
    })

    expect(result.current.selectedItems.has(1)).toBe(true)
    expect(result.current.selectAll).toBe(false)

    // Select all items
    act(() => {
      result.current.handleSelectAll()
    })

    expect(result.current.selectedItems.size).toBe(items.length)
    expect(result.current.selectAll).toBe(true)

    // Deselect one item
    act(() => {
      result.current.handleSelectItem(1)
    })

    expect(result.current.selectedItems.has(1)).toBe(false)
  })
})
