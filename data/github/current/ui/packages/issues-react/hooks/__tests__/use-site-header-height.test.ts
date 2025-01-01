import {renderHook} from '@testing-library/react'
import {useElementPosition, useSiteHeaderHeight} from '../use-site-header-height'

describe('use-site-header-height', () => {
  const mockObserve = jest.fn()
  const mockUnobserve = jest.fn()
  const mockDisconnect = jest.fn()

  beforeEach(() => {
    window.ResizeObserver = jest.fn().mockImplementation(() => ({
      observe: mockObserve,
      unobserve: mockUnobserve,
      disconnect: mockDisconnect,
    }))
  })

  afterEach(() => {
    jest.restoreAllMocks()
    document.body.innerHTML = ''
  })

  describe('useElementPosition', () => {
    it('should return 0 when element is null', () => {
      const {result} = renderHook(() => useElementPosition(null))
      expect(result.current).toBe(0)
    })

    it('should return element bottom position when element exists', () => {
      const mockElement = document.createElement('div')
      Object.defineProperty(mockElement, 'getBoundingClientRect', {
        value: jest.fn().mockReturnValue({bottom: 100}),
      })

      const {result} = renderHook(() => useElementPosition(mockElement))
      expect(result.current).toBe(100)
    })

    it('should set up resize observer when element exists', () => {
      const mockElement = document.createElement('div')
      Object.defineProperty(mockElement, 'getBoundingClientRect', {
        value: jest.fn().mockReturnValue({bottom: 100}),
      })

      renderHook(() => useElementPosition(mockElement))

      expect(mockObserve).toHaveBeenCalledWith(mockElement)
      expect(window.ResizeObserver).toHaveBeenCalled()
    })

    it('should clean up resize observer on unmount', () => {
      const mockElement = document.createElement('div')
      Object.defineProperty(mockElement, 'getBoundingClientRect', {
        value: jest.fn().mockReturnValue({bottom: 100}),
      })

      const {unmount} = renderHook(() => useElementPosition(mockElement))
      unmount()

      expect(mockUnobserve).toHaveBeenCalledWith(mockElement)
      expect(mockDisconnect).toHaveBeenCalled()
    })

    it('should not set up resize observer when element is null', () => {
      renderHook(() => useElementPosition(null))

      expect(window.ResizeObserver).not.toHaveBeenCalled()
    })

    it('should return cached position if element bottom has not changed', () => {
      const mockElement = document.createElement('div')
      const getBoundingClientRect = jest.fn().mockReturnValue({bottom: 100})
      Object.defineProperty(mockElement, 'getBoundingClientRect', {value: getBoundingClientRect})

      const {result, rerender} = renderHook(() => useElementPosition(mockElement))
      expect(result.current).toBe(100)

      rerender()
      expect(result.current).toBe(100)
    })
  })

  describe('useSiteHeaderHeight', () => {
    it('should return combined bottom position when sticky header is not present', () => {
      // Create mock elements
      const header = document.createElement('div')
      Object.defineProperty(header, 'getBoundingClientRect', {
        value: jest.fn().mockReturnValue({bottom: 50}),
      })
      header.classList.add('AppHeader')
      document.body.appendChild(header)

      const staffbar = document.createElement('div')
      Object.defineProperty(staffbar, 'getBoundingClientRect', {
        value: jest.fn().mockReturnValue({bottom: 30}),
      })
      staffbar.id = 'serverstats'
      document.body.appendChild(staffbar)

      const {result} = renderHook(() => useSiteHeaderHeight())
      expect(result.current).toBe(50) // AppHeader bottom position
    })

    it('should return sticky header bottom position when it is greater', () => {
      // Create mock elements
      const header = document.createElement('div')
      Object.defineProperty(header, 'getBoundingClientRect', {
        value: jest.fn().mockReturnValue({bottom: 50}),
      })
      header.classList.add('AppHeader')
      document.body.appendChild(header)

      const staffbar = document.createElement('div')
      Object.defineProperty(staffbar, 'getBoundingClientRect', {
        value: jest.fn().mockReturnValue({bottom: 30}),
      })
      staffbar.id = 'serverstats'
      document.body.appendChild(staffbar)

      const stickyHeader = document.createElement('div')
      Object.defineProperty(stickyHeader, 'getBoundingClientRect', {
        value: jest.fn().mockReturnValue({bottom: 60}),
      })
      stickyHeader.classList.add('js-notification-shelf-offset-top')

      const primaryIssueViewer = document.createElement('div')
      primaryIssueViewer.classList.add('primary-viewer')
      primaryIssueViewer.appendChild(stickyHeader)
      document.body.appendChild(primaryIssueViewer)

      const {result} = renderHook(() => useSiteHeaderHeight())
      expect(result.current).toBe(60) // Sticky header bottom position
    })
  })
})
