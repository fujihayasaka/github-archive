import type {PlaygroundState, ShowModelGettingStartedPayloadSDKEntry} from '../../../../../types'

export function mockSDK(overrides: Partial<ShowModelGettingStartedPayloadSDKEntry> = {}) {
  const baseSDK: ShowModelGettingStartedPayloadSDKEntry = {
    name: 'A Very Nice SDK',
    tocHeadings: [],
    content: "You won't believe these docs.",
    codeSamples: 'print("hello world");',
  }
  return {...baseSDK, ...overrides}
}

export function mockPlaygroundState(overrides: Partial<PlaygroundState> = {}): PlaygroundState {
  const baseState: PlaygroundState = {
    syncInputs: false,
    models: [],
  }
  return {...baseState, ...overrides}
}

export function mockResizeObserver() {
  class MockResizeObserver implements ResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
  Object.defineProperty(window, 'ResizeObserver', {writable: true, configurable: true, value: MockResizeObserver})
}
