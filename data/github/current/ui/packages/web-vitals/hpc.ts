import {wasServerRendered} from '@github-ui/ssr-utils'
import {onLCP} from 'web-vitals/attribution'
import {hasFetchedGQL, hasFetchedJS, isReactAlternate, isReactLazyPayload} from './web-vitals'
import {sendVitals} from './timing-stats'
import type {SoftNavMechanism} from '@github-ui/soft-nav/events'
import {HPCDomInsertionEvent, HPCTimingEvent, type HPCEventTarget} from './hpc-events'
import {getCurrentReactAppName} from '@github-ui/soft-nav/utils'
import {SOFT_NAV_STATE} from '@github-ui/soft-nav/states'

const INSERTION_TIMEOUT = 10000

function getAppName() {
  return getCurrentReactAppName() || 'rails'
}

function isVisible(element: HTMLElement) {
  // Safari doesn't support `checkVisibility` yet.
  if (typeof element.checkVisibility === 'function') return element.checkVisibility()

  return Boolean(element.offsetParent || element.offsetWidth || element.offsetHeight)
}

function setLCPasHPC(soft: boolean, found: boolean) {
  onLCP(({value, attribution}) => {
    window.performance.measure('HPC', {start: 'navigationStart', end: value})
    sendVitals({
      name: 'HPC',
      value,
      soft,
      found,
      gqlFetched: hasFetchedGQL(),
      jsFetched: hasFetchedJS(),
      ssr: wasServerRendered(),
      lazy: isReactLazyPayload(),
      alternate: isReactAlternate(),
      mechanism: 'hard',
      app: getAppName(),
      attribution: {
        element: attribution?.element,
      },
    } as HPCTimingEvent)
  })
}

interface HPCObserverAttributes {
  soft: boolean
  mechanism: SoftNavMechanism | 'hard'
  latestHPCElement: Element | null
}

export class HPCObserver {
  abortController = new AbortController()
  tabHidden = false
  insertionFound = false
  hpcElement: Element | null = null

  soft: boolean
  mechanism: SoftNavMechanism | 'hard'
  latestHPCElement: Element | null
  hpcStart: DOMHighResTimeStamp
  hpcTarget: HPCEventTarget = new EventTarget() as HPCEventTarget
  animationFrame?: number
  dataHPCanimationFrame?: number
  emulatedHPCTimer?: ReturnType<typeof setTimeout>
  listenerOpts: AddEventListenerOptions
  hpcDOMInsertionObserver: MutationObserver | null = null

  constructor({soft, mechanism, latestHPCElement}: HPCObserverAttributes) {
    this.soft = soft
    this.mechanism = mechanism
    this.latestHPCElement = latestHPCElement
    this.hpcStart = soft ? performance.now() : 0
    this.listenerOpts = {capture: true, passive: true, once: true, signal: this.abortController.signal}
  }

  connect() {
    if (!this.soft) {
      // In a hard-load, if the script is evaluated after the `data-hpc` element is rendered,
      // we default the HPC value to LCP.
      const hpcElement = document.querySelector('[data-hpc]')
      if (hpcElement) {
        this.hpcElement = hpcElement
        setLCPasHPC(this.soft, true)
        return
      }

      // if the element is not in the page yet, listen for mutations.
      setTimeout(() => {
        // if no mutations happen after INSERTION_TIMEOUT, default to LCP again
        if (!this.insertionFound) setLCPasHPC(this.soft, false)
      }, INSERTION_TIMEOUT)
    }

    this.setupListeners()
    this.hpcDOMInsertionObserver = this.buildMutationObserver()
    this.hpcDOMInsertionObserver.observe(document, {childList: true, subtree: true})
  }

  disconnect() {
    this.cleanupListeners()
    this.hpcDOMInsertionObserver?.disconnect()
  }

  // Observer to listen to ALL mutations to the DOM. We need to check all added nodes
  // for the `data-hpc` attribue. If none are found, we keep listening until all mutations are done.
  private buildMutationObserver() {
    return new MutationObserver(mutations => {
      let hasDataHPC = false
      let visibleElement = false
      let hpcElement: Element | null = null
      let insertionElement: Element | null = null

      // if the mutation didn't add any nodes, we don't track its HPC
      if (mutations.every(mutation => mutation.addedNodes.length === 0)) return

      for (const mutation of mutations) {
        if (mutation.type !== 'childList') continue

        for (const node of mutation.addedNodes) {
          if (!(node instanceof Element)) continue

          hpcElement = node.hasAttribute('data-hpc') ? node : node.querySelector('[data-hpc]')
          if (hpcElement) {
            this.hpcElement = hpcElement
            if (this.animationFrame) cancelAnimationFrame(this.animationFrame)
            hasDataHPC = true
            break
          }

          // we only care about visible elements
          if (isVisible(node as HTMLElement)) {
            insertionElement = node
            if (this.animationFrame) cancelAnimationFrame(this.animationFrame)
            visibleElement = true
          }
        }

        if (hasDataHPC) break
      }

      if (hasDataHPC && hpcElement) {
        this.reportHPC(hpcElement)
      } else if (visibleElement) {
        const insertionEvent = new HPCDomInsertionEvent(insertionElement)
        this.animationFrame = requestAnimationFrame(() => {
          this.hpcTarget.dispatchEvent(insertionEvent)
        })
      }
    })
  }

  private reportHPC(element: Element) {
    window.performance.measure('HPC', 'navigationStart')
    // data-hpc found, we can stop listening to mutations.
    this.hpcDOMInsertionObserver?.disconnect()
    // only cancel the animation frame if the controller aborts.
    const timingEvent = new HPCTimingEvent(
      this.soft,
      wasServerRendered(),
      isReactLazyPayload(),
      isReactAlternate(),
      this.mechanism,
      true,
      hasFetchedGQL(),
      hasFetchedJS(),
      getAppName(),
      this.hpcStart,
      element,
    )

    this.dataHPCanimationFrame = requestAnimationFrame(() => {
      this.hpcTarget.dispatchEvent(timingEvent)
    })
  }

  private cleanupListeners() {
    document.removeEventListener('touchstart', this.stop, this.listenerOpts)
    document.removeEventListener('mousedown', this.stop, this.listenerOpts)
    document.removeEventListener('keydown', this.stop, this.listenerOpts)
    document.removeEventListener('pointerdown', this.stop, this.listenerOpts)
    document.removeEventListener('visibilitychange', this.onVisibilityChange)
    document.removeEventListener(SOFT_NAV_STATE.RENDER, this.onSoftNavRender)

    this.hpcTarget.removeEventListener('hpc:dom-insertion', this.onDOMInsertion)
    this.hpcTarget.removeEventListener('hpc:timing', this.onHPCTiming)

    this.abortController.signal.removeEventListener('abort', this.onAbort)
  }

  private setupListeners() {
    // Stop listening for HPC events if the user has interacted, as interactions
    // can cause DOM mutations, which we want to avoid capturing for HPC.
    // eslint-disable-next-line github/require-passive-events
    document.addEventListener('touchstart', this.stop, this.listenerOpts)
    document.addEventListener('mousedown', this.stop, this.listenerOpts)
    document.addEventListener('keydown', this.stop, this.listenerOpts)
    document.addEventListener('pointerdown', this.stop, this.listenerOpts)

    // Process HPC events
    this.hpcTarget.addEventListener('hpc:dom-insertion', this.onDOMInsertion, {
      signal: this.abortController.signal,
    })
    this.hpcTarget.addEventListener('hpc:timing', this.onHPCTiming, {signal: this.abortController.signal})
    document.addEventListener(SOFT_NAV_STATE.RENDER, this.onSoftNavRender)

    // If the user changes tab, we don't want to send the recorded metrics since it may send garbage data.
    document.addEventListener('visibilitychange', this.onVisibilityChange, {
      signal: this.abortController.signal,
    })

    // If the stop event is triggered, we want to stop listening to DOM mutations.
    this.abortController.signal.addEventListener('abort', this.onAbort)
  }

  stop = () => {
    this.abortController.abort()
  }

  onDOMInsertion = (e: HPCDomInsertionEvent) => {
    this.insertionFound = true
    clearTimeout(this.emulatedHPCTimer)
    // Whenever we see a DOM insertion, we keep track of when it happened.
    const event = new HPCTimingEvent(
      this.soft,
      wasServerRendered(),
      isReactLazyPayload(),
      isReactAlternate(),
      this.mechanism,
      false,
      hasFetchedGQL(),
      hasFetchedJS(),
      getAppName(),
      this.hpcStart,
      e.element,
    )

    // If no mutations happen after the timeout, we assume that the DOM is fully loaded, so we send the
    // last seen mutation values.
    this.emulatedHPCTimer = setTimeout(() => this.hpcTarget.dispatchEvent(event), INSERTION_TIMEOUT)
  }

  onHPCTiming = (e: HPCTimingEvent) => {
    if (!this.tabHidden && e.value < 60_000) sendVitals(e)

    this.abortController.abort()
  }

  onVisibilityChange = () => {
    this.tabHidden = true
    this.abortController.abort()
  }

  onSoftNavRender = () => {
    const currentHPCElement = document.querySelector('[data-hpc]')
    this.hpcElement = currentHPCElement

    // In case the soft navigation doesn't change the root data-hpc element, the MutationObserver
    // won't catch it, so we use the soft navigation timing as HPC.
    if (!currentHPCElement || currentHPCElement !== this.latestHPCElement) return

    this.reportHPC(currentHPCElement)
  }

  onAbort = () => {
    if (this.dataHPCanimationFrame) cancelAnimationFrame(this.dataHPCanimationFrame)
    if (this.animationFrame) cancelAnimationFrame(this.animationFrame)
    clearTimeout(this.emulatedHPCTimer)
    this.disconnect()
  }
}
