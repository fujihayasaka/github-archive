// @ts-check
import {applyDefaultClientEnvMock} from '@github-ui/client-env/mock'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {userAnalyticsTestSetup} from '@github-ui/analytics-test-utils/msw'
import {cleanup, configure as configureTestingLibrary, prettyDOM} from '@testing-library/react'
import {use as chaiUse} from 'chai'
import {chaiA11yAxe} from 'chai-a11y-axe'
import chaiDom from 'chai-dom'
import {afterEach, beforeEach} from 'vitest'
import failOnConsole from 'vitest-fail-on-console'
import {fixtureCleanup} from './browser-tests'

// Register chai plugins
chaiUse(chaiA11yAxe)
chaiUse(chaiDom)

// Setting beforeEach on globalThis for applyDefaultClientEnvMock
globalThis.beforeEach = beforeEach
applyDefaultClientEnvMock()

// Set up meta tags for analytics testing and register handlers
userAnalyticsTestSetup()

// Utility to make vitest tests fail when certain console outputs are used
failOnConsole()

afterEach(() => {
  if (!process.env.HEADED_BROWSER_ENABLED) {
    fixtureCleanup()
    cleanup()
  }
  getQueryClient().clear()
})

/**
 * Exclude SVG elements from default debugging output of testing-library
 * Mirrors the jest impl in ui/packages/jest/jest-setup.ts
 *
 * @param {string | null} message
 * @param {Element} container
 * @returns {Error}
 */
function getElementError(message, container) {
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
