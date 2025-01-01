export class ReactQueryDevtoolToggleEvent extends Event {
  static EVENT_NAME = 'react-query-devtool-toggle' as const
  constructor() {
    super(ReactQueryDevtoolToggleEvent.EVENT_NAME)
  }
}
export class ReactQueryDevtoolResizeEvent extends Event {
  static EVENT_NAME = 'react-query-devtool-resize' as const
  constructor() {
    super(ReactQueryDevtoolResizeEvent.EVENT_NAME)
  }
}

export function subscribeToToggleEvent(notify: () => void) {
  document.addEventListener(ReactQueryDevtoolToggleEvent.EVENT_NAME, notify)
  return () => {
    document.removeEventListener(ReactQueryDevtoolToggleEvent.EVENT_NAME, notify)
  }
}

export function subscribeToBodyResize(notify: () => void) {
  const resizeObs = new ResizeObserver(notify)
  resizeObs.observe(document.body)
  return () => {
    resizeObs.disconnect()
  }
}

export function subscribeToSessionResize(notify: () => void) {
  document.addEventListener(ReactQueryDevtoolResizeEvent.EVENT_NAME, notify)
  return () => {
    document.removeEventListener(ReactQueryDevtoolResizeEvent.EVENT_NAME, notify)
  }
}
