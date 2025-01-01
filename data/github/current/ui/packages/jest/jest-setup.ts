import './fetch-polyfills'
import '@testing-library/jest-dom'

import {randomUUID} from 'node:crypto'
import {clearImmediate} from 'node:timers'
import failOnConsole from 'jest-fail-on-console'
import {fetch, Headers, Request, Response, setGlobalOrigin} from 'undici'
import {userAnalyticsTestSetup} from '@github-ui/analytics-test-utils'
import {applyDefaultClientEnvMock} from '@github-ui/client-env/mock'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {ssrShimFileMap} from '@github-ui/ssr-shims'

import {configure as configureTestingLibrary, prettyDOM} from '@testing-library/dom'

const CI = Boolean(JSON.parse(process.env.CI ?? 'false'))
jest.retryTimes(Number(process.env.TEST_RETRIES_TIMES ?? CI ? '4' : '0'), {logErrorsBeforeRetry: true})

// Node 18+ has Broadcast channel defined, but creating one will leave open handles preventing Jest from exiting
global.BroadcastChannel = jest.fn().mockImplementation(() => ({
  addEventListener: jest.fn(),
}))

// we only want to mock browser globals in DOM (or js-dom) environments – not in SSR / node
if (typeof document !== 'undefined') {
  window.crypto.randomUUID ||= () => randomUUID()

  /**
   * Setting the global origin for requests so that relative urls work in our jest tests
   */
  setGlobalOrigin(window.location.origin)
  // @ts-expect-error sometimes the polyfill types don't match the dom ones perfectly
  globalThis.fetch = fetch
  // // @ts-expect-error sometimes the polyfill types don't match the dom ones perfectly
  globalThis.Blob = Blob
  globalThis.File = File
  // @ts-expect-error sometimes the polyfill types don't match the dom ones perfectly
  globalThis.Headers = Headers
  // @ts-expect-error sometimes the polyfill types don't match the dom ones perfectly
  globalThis.Request = Request
  // @ts-expect-error sometimes the polyfill types don't match the dom ones perfectly
  globalThis.Response = Response
  globalThis.clearImmediate = clearImmediate

  window.ResizeObserver = jest.fn().mockImplementation(() => ({
    observe: jest.fn(),
    unobserve: jest.fn(),
    disconnect: jest.fn(),
  }))

  window.requestIdleCallback = jest.fn()

  // IntersectionObserver is not supported in JSDOM, which does not contain
  // DOM layout functionality. https://github.com/jsdom/jsdom/issues/2032
  window.IntersectionObserver = jest.fn().mockImplementation(() => ({
    observe: jest.fn(),
    unobserve: jest.fn(),
    takeRecords: jest.fn(),
    disconnect: jest.fn(),

    root: null,
    rootMargin: [],
    thresholds: [],
  }))

  window.fetch = mockFetch.fetch

  // @ts-expect-error not defining all properties
  window.CSS = {
    supports: jest.fn(),
    escape: jest.fn(),
  }

  /**
   * Required for internal usage of matchMedia in primer/react
   * this is not implemented in JSDOM, and until it is we'll need to polyfill
   * https://jestjs.io/docs/manual-mocks#mocking-methods-which-are-not-implemented-in-jsdom
   */
  beforeEach(() => {
    Object.defineProperty(window, 'matchMedia', {
      writable: true,
      value: jest.fn().mockImplementation(query => ({
        matches: false,
        media: query,
        onchange: null,
        addListener: jest.fn(), // deprecated
        removeListener: jest.fn(), // deprecated
        addEventListener: jest.fn(),
        removeEventListener: jest.fn(),
        dispatchEvent: jest.fn(),
      })),
    })
  })

  Object.defineProperty(window, 'scrollTo', {
    writable: true,
    value: jest.fn(),
  })

  // @ts-expect-error sometimes the polyfill types don't match the dom ones perfectly
  window.performance.markResourceTiming = jest.fn()
  window.performance.clearResourceTimings = jest.fn()
  window.performance.mark = jest.fn()
  window.performance.measure = jest.fn()
  window.performance.getEntriesByName = jest.fn().mockReturnValue([])
  window.performance.clearMarks = jest.fn()
  window.performance.clearMeasures = jest.fn()
} else {
  /**
   * Our custom elements all extend from HTMLElement, which will fail
   * when we run Jest in a node environment. We can shim HTMLElement with Object
   * to avoid errors. There is a similar shim for SSR in webpack-alloy.config.js
   */
  global.HTMLElement = Object as never

  const skipModuleShims = ['invokers-polyfill/fn', '@oddbird/popover-polyfill/fn', '#minproc', '#minpath', '#minurl']

  /**
   * When we run Jest in a node environment, we need to apply the same shims that
   * will be used in our SSR environment. We do this by mocking the imports and
   * returning the shim exports instead.
   */
  const shims = Object.entries(ssrShimFileMap)
  for (const [file, shimPath] of shims) {
    if (!skipModuleShims.includes(file)) {
      jest.mock(file, () => {
        // eslint-disable-next-line import/no-dynamic-require, @typescript-eslint/no-require-imports
        return require(shimPath)
      })
    }
  }
}

const failOnAllConsoleMessages = process.env.CI === 'true'

/**
 * Memex currently logs errors/warnings in some of their tests. In order to get a shared
 * base Jest config, we need to ignore these for now. Once they are cleaned up, this
 * exception should be removed.
 */
const isMemexPackage = process.env.PWD?.includes('ui/packages/memex')

failOnConsole({
  shouldFailOnWarn: !isMemexPackage,
  shouldFailOnError: !isMemexPackage,

  shouldFailOnDebug: failOnAllConsoleMessages,
  shouldFailOnInfo: failOnAllConsoleMessages,
  shouldFailOnLog: failOnAllConsoleMessages,

  silenceMessage(message, methodName) {
    // silence messages related to JSDOM not implementing navigation
    if (methodName === 'error' && message.startsWith('Error: Not implemented: navigation (except hash changes)')) {
      return true
    }
    return false
  },
})

userAnalyticsTestSetup()
applyDefaultClientEnvMock()

/**
 * Required for internal usage of dialog in primer/react
 * this is not implemented in JSDOM, and until it is we'll need to polyfill
 * https://github.com/jsdom/jsdom/issues/3294
 * https://jestjs.io/docs/manual-mocks#mocking-methods-which-are-not-implemented-in-jsdom
 * we only want to mock browser globals in DOM (or js-dom) environments – not in SSR / node
 */
if (typeof document !== 'undefined') {
  global.HTMLDialogElement.prototype.showModal = jest.fn(function mock(this: HTMLDialogElement) {
    this.open = true
  })

  global.HTMLDialogElement.prototype.close = jest.fn(function mock(this: HTMLDialogElement) {
    this.open = false
  })

  global.HTMLElement.prototype.scrollIntoView = jest.fn()
  global.HTMLElement.prototype.scrollTo = jest.fn()

  global.Range.prototype.getBoundingClientRect = jest.fn().mockReturnValue({
    top: 1,
    bottom: 1,
    right: 1,
    left: 1,
    height: 1,
    width: 1,
    x: 1,
    y: 1,
  })
}

afterEach(() => {
  getQueryClient().clear()
})

jest.mock('@testing-library/user-event', () => {
  // user-event attaches afterEach and afterAll hooks that reset the clipboard mocks after every test. So if we always
  // import it and an SSR-only test imports this (ie, through a utils file that is shared with non-SSR tests), it will
  // error on cleanup when user-event tries to access `navigator.clipboard`.
  if (typeof document !== 'undefined') {
    return jest.requireActual('@testing-library/user-event')
  }
  const userEvent = {
    setup: jest.fn(),
    clear: jest.fn(),
    click: jest.fn(),
    copy: jest.fn(),
    cut: jest.fn(),
    dblClick: jest.fn(),
    deselectOptions: jest.fn(),
    hover: jest.fn(),
    keyboard: jest.fn(),
    pointer: jest.fn(),
    paste: jest.fn(),
    selectOptions: jest.fn(),
    tripleClick: jest.fn(),
    type: jest.fn(),
    unhover: jest.fn(),
    upload: jest.fn(),
    tab: jest.fn(),
  }
  return {
    default: userEvent,
    userEvent,
  }
})

// Exclude SVG elements from default debugging output
function getElementError(message: string | null, container: Element): Error {
  const err = new Error(`${message}
Ignored nodes: script, style, comments, svg descendants

${prettyDOM(container, undefined, {
  filterNode(node) {
    if (node.nodeType === node.COMMENT_NODE) return false
    if (node instanceof SVGElement && !(node instanceof SVGSVGElement)) return false
    if (node instanceof HTMLScriptElement || node instanceof HTMLStyleElement) return false
    return true
  },
})}`)

  if (Error.captureStackTrace) {
    Error.captureStackTrace(err, getElementError)
  }

  return err
}

configureTestingLibrary({
  getElementError,
})

jest.mock('@github/browser-support', () => {
  return {
    isSupported: jest.fn(),
    isPolyfilled: jest.fn(),
    apply: jest.fn(),
  }
})
