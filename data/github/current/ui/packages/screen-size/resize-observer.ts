let resizeObserver: ResizeObserver | null = null
let frame: number | null = null
const subscribers: Set<() => void> = new Set()

function getResizeObserver(): ResizeObserver {
  if (!resizeObserver) {
    resizeObserver = new ResizeObserver(() => {
      if (frame) {
        // already scheduled to inform subscribers in the next animation frame
        return
      }
      frame = requestAnimationFrame(() => {
        frame = null
        for (const subscribeCallback of subscribers) {
          subscribeCallback()
        }
      })
    })
    resizeObserver.observe(document.documentElement)
  }
  return resizeObserver
}

function cleanupResizeObserver() {
  if (subscribers.size === 0 && resizeObserver) {
    resizeObserver.disconnect()
    resizeObserver = null
  }
}

export function subscribe(notify: () => void) {
  subscribers.add(notify)
  getResizeObserver()

  return () => {
    subscribers.delete(notify)
    cleanupResizeObserver()
  }
}
