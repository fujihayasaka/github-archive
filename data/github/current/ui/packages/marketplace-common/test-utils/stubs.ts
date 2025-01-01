export function mockResizeObserver() {
  class MockResizeObserver implements ResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
  Object.defineProperty(window, 'ResizeObserver', {writable: true, configurable: true, value: MockResizeObserver})
}

export function mockMatchMedia(matches = '(min-width: 1000px)') {
  return jest.spyOn(window, 'matchMedia').mockImplementation(media => ({
    addListener: jest.fn(),
    removeListener: jest.fn(),
    matches: media === matches,
    addEventListener: jest.fn(),
    removeEventListener: jest.fn(),
    dispatchEvent: jest.fn(),
    onchange: jest.fn(),
    media,
  }))
}
