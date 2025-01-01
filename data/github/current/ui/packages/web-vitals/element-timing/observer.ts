import {SOFT_NAV_STATE} from '@github-ui/soft-nav/states'
import {ssrSafeDocument, ssrSafeWindow} from '@github-ui/ssr-utils'
import {ElementTimingMetric} from './metric'

const supportsElementTiming = ssrSafeWindow && 'PerformanceElementTiming' in ssrSafeWindow

type ElementTimingTCallback = (elementTiming: ElementTimingMetric, opts: {url?: string}) => void

interface PerformanceElementTiming extends PerformanceEntry {
  renderTime: number
  observer?: PerformanceObserver
  element: Element
  identifier: string
}
/*
 * The ElementTimingObserver is responsible for listening to PerformanceElementTiming events and reporting them.
 */
export class ElementTimingObserver {
  cb: ElementTimingTCallback
  observer?: PerformanceObserver
  url?: string

  constructor(cb: ElementTimingTCallback) {
    this.cb = cb
    this.setupListeners()
  }

  setupListeners() {
    if (!supportsElementTiming) return

    // SOFT_NAV_STATE.RENDER is dispatched when the soft navigation finished rendering.
    // That means that the previous page is fully hidden so we can stop listening for its events.
    ssrSafeDocument?.addEventListener(SOFT_NAV_STATE.RENDER, () => {
      this.reset()
    })
  }

  observe(initialLoad = true) {
    if (!supportsElementTiming) return

    this.observer = new PerformanceObserver(list => {
      const entries = list.getEntries() as PerformanceElementTiming[]
      for (const {renderTime, element, identifier} of entries) {
        this.report(new ElementTimingMetric(renderTime, element, identifier))
      }
    })

    this.observer.observe({
      type: 'element',
      // buffered events are important on first page load since we may have missed
      // a few until the observer was set up.
      buffered: initialLoad,
    })
  }

  report(metric: ElementTimingMetric) {
    this.cb(metric, {url: this.url})
  }

  teardown() {
    this.observer?.takeRecords()
    this.observer?.disconnect()
  }

  reset() {
    this.teardown()
    this.observe(false)
  }
}
