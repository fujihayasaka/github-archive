import {renderHook} from '@testing-library/react'
import {act} from 'react'

import {useSelectedIndex} from '../use-selected-index'

describe('useSelectedIndex', () => {
  it('should increment', () => {
    const {result} = renderHook(() => useSelectedIndex(3))
    const {selectNext} = result.current

    expect(result.current.selectedIndex).toBe(0)

    // Iterate through available indexes
    act(() => selectNext())
    expect(result.current.selectedIndex).toBe(1)
    act(() => selectNext())
    expect(result.current.selectedIndex).toBe(2)
    act(() => selectNext())
    expect(result.current.selectedIndex).toBe(3)

    // Selected index should wrap around to the start
    act(() => selectNext())
    expect(result.current.selectedIndex).toBe(0)
  })

  it('should decrement', () => {
    const {result} = renderHook(() => useSelectedIndex(3))
    const {selectPrevious} = result.current

    expect(result.current.selectedIndex).toBe(0)

    // Iterate through available indexes
    act(() => selectPrevious())
    expect(result.current.selectedIndex).toBe(3)
    act(() => selectPrevious())
    expect(result.current.selectedIndex).toBe(2)
    act(() => selectPrevious())
    expect(result.current.selectedIndex).toBe(1)
    act(() => selectPrevious())
    expect(result.current.selectedIndex).toBe(0)

    // Selected index should wrap around to the end
    act(() => selectPrevious())
    expect(result.current.selectedIndex).toBe(3)
  })

  describe('when maximum changes', () => {
    describe('and selectedIndex is undefined', () => {
      it('should not change selectedIndex', () => {
        const {result, rerender} = renderHook((props: {maximum: number}) => useSelectedIndex(props.maximum), {
          initialProps: {maximum: 3},
        })

        expect(result.current.selectedIndex).toBe(0)
        rerender({maximum: 1})
        expect(result.current.selectedIndex).toBe(0)
      })
    })

    describe('and selectedIndex is within the new maximum', () => {
      it('should not change selectedIndex', () => {
        const {result, rerender} = renderHook((props: {maximum: number}) => useSelectedIndex(props.maximum), {
          initialProps: {maximum: 3},
        })
        const {selectNext} = result.current

        expect(result.current.selectedIndex).toBe(0)
        act(() => selectNext())
        act(() => selectNext())
        expect(result.current.selectedIndex).toBe(2)

        rerender({maximum: 2})
        expect(result.current.selectedIndex).toBe(2)
      })
    })

    describe('and selectedIndex is greater than the new maximum', () => {
      it('should set selectedIndex to the new maximum', () => {
        const {result, rerender} = renderHook((props: {maximum: number}) => useSelectedIndex(props.maximum), {
          initialProps: {maximum: 3},
        })
        const {selectPrevious} = result.current

        expect(result.current.selectedIndex).toBe(0)
        act(() => selectPrevious())
        expect(result.current.selectedIndex).toBe(3)

        rerender({maximum: 1})
        expect(result.current.selectedIndex).toBe(1)
      })
    })
  })
})
