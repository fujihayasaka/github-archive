import {act, renderHook} from '@testing-library/react'

import useIsVisible, {ObserverContext} from '../../client/components/board/hooks/use-is-visible'
import {mockGetBoundingClientRect} from '../components/board/board-test-helper'

describe('useIsVisible', () => {
  beforeAll(() => {
    mockGetBoundingClientRect()
  })

  describe('isCurrentlyVisible', () => {
    it('returns false for null element ref', () => {
      const {result: nullRef} = renderHook(() => useIsVisible({ref: {current: null}}))
      expect(nullRef.current.isCurrentlyVisible()).toBe(false)
    })

    it('returns false if missing rootBounds', () => {
      const element = document.createElement('div')
      const {result} = renderHook(() => useIsVisible({ref: {current: element}}))
      expect(result.current.isCurrentlyVisible()).toBe(false)
    })

    const scenarios = [
      {
        elementRect: {top: 5, left: 5, bottom: 95, right: 95, width: 90, height: 90},
        rootBounds: {top: 0, left: 0, bottom: 100, right: 100, width: 100, height: 100},
        expectedResult: true,
      }, // Element is fully within root bounds
      {
        elementRect: {top: 101, left: 0, bottom: 201, right: 100, width: 100, height: 100},
        rootBounds: {top: 0, left: 0, bottom: 100, right: 100, width: 100, height: 100},
        expectedResult: false,
      }, // Element is fully outside root bounds (below)
      {
        elementRect: {top: 0, left: 0, bottom: 100, right: 100, width: 100, height: 100},
        rootBounds: {top: 101, left: 0, bottom: 201, right: 100, width: 100, height: 100},
        expectedResult: false,
      }, // Element is fully outside root bounds (above)
      {
        elementRect: {top: 0, left: 101, bottom: 100, right: 201, width: 100, height: 100},
        rootBounds: {top: 0, left: 0, bottom: 100, right: 100, width: 100, height: 100},
        expectedResult: false,
      }, // Element is fully outside root bounds (left)
      {
        elementRect: {top: 0, left: 0, bottom: 100, right: 100, width: 100, height: 100},
        rootBounds: {top: 0, left: 101, bottom: 100, right: 201, width: 100, height: 100},
        expectedResult: false,
      }, // Element is fully outside root bounds (right)
      {
        elementRect: {top: 100, left: 0, bottom: 200, right: 100, width: 100, height: 100},
        rootBounds: {top: 0, left: 0, bottom: 100, right: 100, width: 100, height: 100},
        expectedResult: true,
      }, // Element overlaps bottom edge of root bounds
      {
        elementRect: {top: 0, left: 0, bottom: 100, right: 100, width: 100, height: 100},
        rootBounds: {top: 100, left: 0, bottom: 200, right: 100, width: 100, height: 100},
        expectedResult: true,
      }, // Element overlaps top edge of root bounds
      {
        elementRect: {top: 0, left: 100, bottom: 100, right: 200, width: 100, height: 100},
        rootBounds: {top: 0, left: 0, bottom: 100, right: 100, width: 100, height: 100},
        expectedResult: true,
      }, // Element overlaps right edge of root bounds
      {
        elementRect: {top: 0, left: 0, bottom: 100, right: 100, width: 100, height: 100},
        rootBounds: {top: 0, left: 100, bottom: 100, right: 200, width: 100, height: 100},
        expectedResult: true,
      }, // Element overlaps left edge of root bounds
    ]
    for (const scenario of scenarios) {
      it(`returns ${scenario.expectedResult} for elementRect: ${JSON.stringify(
        scenario.elementRect,
      )} and rootBounds: ${JSON.stringify(scenario.rootBounds)}`, () => {
        // Mocks getBoundingClientRect for any element
        mockGetBoundingClientRect(scenario.elementRect)
        const element = document.createElement('div')
        const providerState = {
          observer: new IntersectionObserver(jest.fn()),
          elMapRef: {current: new Map()},
          avgRef: {current: {avg: 0, count: 0}},
        }
        const {result, rerender} = renderHook(() => useIsVisible({ref: {current: element}}), {
          wrapper: ({children}) => (
            <ObserverContext.Provider value={providerState}>{children}</ObserverContext.Provider>
          ),
        })
        const entry = providerState.elMapRef.current.get(element)
        expect(entry).toBeDefined()
        act(() => {
          // Mock setting the root bounds on observation
          entry?.setObservedRootBounds(scenario.rootBounds as IntersectionObserverEntry['rootBounds'])
        })
        rerender()
        expect(result.current.isCurrentlyVisible()).toBe(scenario.expectedResult)
      })
    }
  })
})
