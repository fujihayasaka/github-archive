import {renderHook, act} from '@testing-library/react'
import {useSearchParams} from 'react-router-dom'
import {usePagination} from '../use-pagination'

jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useSearchParams: jest.fn(),
}))

const mockUseSearchParams = useSearchParams as jest.MockedFunction<typeof useSearchParams>

let mockSearchParams: URLSearchParams
let mockSetSearchParams: jest.Mock

beforeEach(() => {
  mockSearchParams = new URLSearchParams()
  mockSetSearchParams = jest.fn()
  mockUseSearchParams.mockReturnValue([mockSearchParams, mockSetSearchParams])
})

afterEach(() => {
  jest.clearAllMocks()
})

const createTestItems = (count: number) =>
  Array.from({length: count}, (_, i) => ({
    id: i + 1,
    name: `Item ${i + 1}`,
  }))

describe('usePagination', () => {
  test('handles single page of items', () => {
    const items = createTestItems(3)
    const {result} = renderHook(() => usePagination(items, {pageSize: 5}))

    expect(result.current.currentPage).toBe(1)
    expect(result.current.totalPages).toBe(1)
    expect(result.current.paginatedItems).toHaveLength(3)
  })

  test('returns the first page by default', () => {
    const items = createTestItems(5)
    const {result} = renderHook(() => usePagination(items, {pageSize: 3}))

    expect(result.current.currentPage).toBe(1)
    expect(result.current.paginatedItems).toHaveLength(3)
    expect(result.current.paginatedItems[0]).toEqual({id: 1, name: 'Item 1'})
  })

  test('handles invalid page numbers in URL', () => {
    mockSearchParams.set('page', 'invalid')
    const items = createTestItems(5)
    const {result} = renderHook(() => usePagination(items))

    expect(result.current.currentPage).toBe(1) // Should default to 1
  })

  test('handles negative page numbers', () => {
    mockSearchParams.set('page', '-2')
    const items = createTestItems(5)
    const {result} = renderHook(() => usePagination(items))

    expect(result.current.currentPage).toBe(1) // Should default to 1
  })

  test('handles page numbers beyond total pages', () => {
    mockSearchParams.set('page', '999')
    const items = createTestItems(5)
    const {result} = renderHook(() => usePagination(items, {pageSize: 2}))

    expect(result.current.currentPage).toBe(999)
    expect(result.current.paginatedItems).toEqual([]) // Slice will return empty array
  })

  test('uses a custom page size when provided', () => {
    const items = createTestItems(10)
    const {result} = renderHook(() => usePagination(items, {pageSize: 4}))

    expect(result.current.pageSize).toBe(4)
    expect(result.current.paginatedItems).toHaveLength(4)
  })

  test('calculates total pages correctly', () => {
    const items = createTestItems(11)
    const {result} = renderHook(() => usePagination(items, {pageSize: 5}))

    expect(result.current.totalPages).toBe(3) // 11 / 5 = 3 pages
  })

  test('handles empty items array', () => {
    const {result} = renderHook(() => usePagination([]))

    expect(result.current.currentPage).toBe(1)
    expect(result.current.totalPages).toBe(0)
    expect(result.current.paginatedItems).toEqual([])
  })

  test('should return correct items for each page', () => {
    const items = createTestItems(6)
    const {result, rerender} = renderHook(() => usePagination(items, {pageSize: 2}))

    // Page 1
    expect(result.current.paginatedItems).toHaveLength(2)
    expect(result.current.paginatedItems[0]).toEqual({id: 1, name: 'Item 1'})
    expect(result.current.paginatedItems[1]).toEqual({id: 2, name: 'Item 2'})

    // Navigate to page 2
    act(() => {
      result.current.navigateToPage(2)
    })
    rerender()

    mockSearchParams.set('page', '2')
    mockUseSearchParams.mockReturnValue([mockSearchParams, mockSetSearchParams])

    // Rerender to pick up the new page
    const {result: result2} = renderHook(() => usePagination(items, {pageSize: 2}))

    expect(result2.current.paginatedItems[0]).toEqual({id: 3, name: 'Item 3'})
    expect(result2.current.paginatedItems[1]).toEqual({id: 4, name: 'Item 4'})
  })

  test('reads the current page from URL params', () => {
    const items = createTestItems(8)
    mockSearchParams.set('page', '2')
    const {result} = renderHook(() => usePagination(items, {pageSize: 3}))

    expect(result.current.currentPage).toBe(2)
    expect(result.current.paginatedItems[0]).toEqual({id: 4, name: 'Item 4'})
  })

  test('updates URL params when navigating to a page', () => {
    const items = createTestItems(5)
    const {result} = renderHook(() => usePagination(items))

    act(() => {
      result.current.navigateToPage(3)
    })

    expect(mockSetSearchParams).toHaveBeenCalledWith(
      expect.objectContaining({
        toString: expect.any(Function),
      }),
    )

    const calledParams = mockSetSearchParams.mock.calls[0][0]
    expect(calledParams.get('page')).toBe('3')
  })

  test('memoizes paginated items', () => {
    const items = createTestItems(5)
    const {result, rerender} = renderHook(() => usePagination(items))

    const firstRenderItems = result.current.paginatedItems

    // Rerender without changing anything
    rerender()

    expect(result.current.paginatedItems).toBe(firstRenderItems) // Same reference
  })

  test('recalculates when items change', () => {
    const initialItems = createTestItems(5)
    const {result, rerender} = renderHook(({items}) => usePagination(items), {
      initialProps: {items: initialItems},
    })

    const firstRenderItems = result.current.paginatedItems

    // Change items
    const newItems = createTestItems(3).map(item => ({...item, name: `New ${item.name}`}))
    rerender({items: newItems})

    expect(result.current.paginatedItems).not.toBe(firstRenderItems)
    expect(result.current.paginatedItems[0]).toEqual({id: 1, name: 'New Item 1'})
  })
})
