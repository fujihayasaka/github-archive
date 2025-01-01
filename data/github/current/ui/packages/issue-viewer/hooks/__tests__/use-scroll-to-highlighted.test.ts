import {renderHook, waitFor} from '@testing-library/react'
import {useNewScrollToHighlighted} from '../use-scroll-to-highlighted'
import {isFeatureEnabled} from '@github-ui/feature-flags'

let highlightedItemRef: React.MutableRefObject<HTMLDivElement | null>
let mockScrollIntoView: jest.Mock
let mockScrollBy: jest.SpyInstance
let mockIntersectionObserver: jest.Mock
let observe: jest.Mock
let unobserve: jest.Mock
let disconnect: jest.Mock

jest.mock('@github-ui/feature-flags', () => {
  const actualFeatureFlags = jest.requireActual('@github-ui/feature-flags')
  {
    return {
      ...actualFeatureFlags,
      isFeatureEnabled: jest.fn(),
    }
  }
})

function isFeatureEnabledMockValue(FF: string) {
  ;(isFeatureEnabled as jest.Mock).mockImplementation(() => (featureName: string) => featureName === FF)
}

const notificationShelf = document.createElement('div')
const notificationShelfHeight = 200
notificationShelf.setAttribute('data-testid', 'notification-shelf')
notificationShelf.setAttribute('id', 'notification-shelf')
notificationShelf.getBoundingClientRect = jest.fn().mockReturnValue({height: notificationShelfHeight} as DOMRect)

const highlightedItem = document.createElement('div')

describe('useNewScrollToHighlighted', () => {
  beforeEach(() => {
    mockScrollIntoView = jest.fn()
    mockScrollBy = jest.spyOn(window, 'scrollBy').mockImplementation(() => {})

    highlightedItemRef = {current: highlightedItem}
    if (highlightedItemRef.current) {
      highlightedItemRef.current.innerHTML = `<div id="child1"></div>`
      highlightedItemRef.current.scrollIntoView = mockScrollIntoView
    }

    observe = jest.fn()
    unobserve = jest.fn()
    disconnect = jest.fn()
    mockIntersectionObserver = jest.fn(() => ({
      observe,
      unobserve,
      disconnect,
    }))

    window.IntersectionObserver = mockIntersectionObserver
  })

  afterEach(() => {
    mockScrollBy.mockRestore()
    jest.clearAllMocks()
    document.body.innerHTML = ''
  })

  describe('observer', () => {
    it('uses the observer when FF is disabled', async () => {
      const {result} = renderHook(() => useNewScrollToHighlighted(true, highlightedItemRef, 'highlightedEventId', true))

      await waitFor(() => result.current)

      expect(mockIntersectionObserver).toHaveBeenCalledTimes(1)
      expect(observe).toHaveBeenCalledTimes(1)
    })

    it('does not use the observer when FF is enabled', async () => {
      isFeatureEnabledMockValue('issues_react_disable_sticky_header_observer')
      const {result} = renderHook(() => useNewScrollToHighlighted(true, highlightedItemRef, 'highlightedEventId', true))

      await waitFor(() => result.current)

      expect(mockIntersectionObserver).not.toHaveBeenCalledTimes(1)
      expect(observe).not.toHaveBeenCalledTimes(1)
    })
  })

  describe('notification-shelf', () => {
    it('scrolls correctly if the notification shelf is present', async () => {
      document.body.appendChild(notificationShelf)
      document.body.appendChild(highlightedItem)
      isFeatureEnabledMockValue('issues_react_disable_sticky_header_observer')

      const {result} = renderHook(() => useNewScrollToHighlighted(true, highlightedItemRef, 'highlightedEventId', true))

      await waitFor(() => result.current)

      expect(highlightedItem).toBeVisible()
      expect(notificationShelf).toBeVisible()

      // called twice after checking that the notification shelf is present
      expect(mockScrollBy).toHaveBeenCalledTimes(2)
    })

    it('scrolls correctly if the notification shelf is not present', async () => {
      document.body.appendChild(highlightedItem)
      isFeatureEnabledMockValue('issues_react_disable_sticky_header_observer')

      const {result} = renderHook(() => useNewScrollToHighlighted(true, highlightedItemRef, 'highlightedEventId', true))

      await waitFor(() => result.current)

      expect(highlightedItem).toBeVisible()
      expect(notificationShelf).not.toBeVisible()

      // called once since the notification shelf is not present
      expect(mockScrollBy).toHaveBeenCalledTimes(1)
    })
  })
})
