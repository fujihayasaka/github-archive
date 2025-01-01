import type {SoftNavMechanism} from '@github-ui/soft-nav/events'
import {getSelector} from './get-selector'

export interface HPCEventTarget extends EventTarget {
  addEventListener(
    type: 'hpc:timing',
    listener: (event: HPCTimingEvent) => void,
    options?: boolean | AddEventListenerOptions,
  ): void
  addEventListener(
    type: 'hpc:dom-insertion',
    listener: (event: HPCDomInsertionEvent) => void,
    options?: boolean | AddEventListenerOptions,
  ): void
  addEventListener(type: string, listener: (event: Event) => void, options?: boolean | AddEventListenerOptions): void

  removeEventListener(
    type: 'hpc:timing',
    listener: (event: HPCTimingEvent) => void,
    options?: boolean | AddEventListenerOptions,
  ): void
  removeEventListener(
    type: 'hpc:dom-insertion',
    listener: (event: HPCDomInsertionEvent) => void,
    options?: boolean | AddEventListenerOptions,
  ): void
  removeEventListener(type: string, listener: (event: Event) => void, options?: boolean | AddEventListenerOptions): void
}

export class HPCTimingEvent extends Event {
  name = 'HPC' as const
  value: number
  attribution: {
    element?: string
  }

  declare soft: boolean
  declare ssr: boolean
  declare lazy: boolean
  declare alternate: boolean
  declare mechanism: SoftNavMechanism | 'hard'
  declare found: boolean
  declare gqlFetched: boolean
  declare jsFetched: boolean
  declare app: string

  constructor(
    soft: boolean,
    ssr: boolean,
    lazy: boolean,
    alternate: boolean,
    mechanism: SoftNavMechanism | 'hard',
    found: boolean,
    gqlFetched: boolean,
    jsFetched: boolean,
    app: string,
    start: number,
    element: Element | null,
  ) {
    super('hpc:timing')
    this.soft = soft
    this.ssr = ssr
    this.lazy = lazy
    this.alternate = alternate
    this.mechanism = mechanism
    this.found = found
    this.gqlFetched = gqlFetched
    this.jsFetched = jsFetched
    this.app = app

    this.value = performance.now() - start
    this.attribution = {
      element: getSelector(element),
    }
  }
}

export class HPCDomInsertionEvent extends Event {
  declare element: Element | null
  constructor(element: Element | null) {
    super('hpc:dom-insertion')
    this.element = element
  }
}
