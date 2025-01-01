import {afterEach, beforeEach} from 'vitest'
import {applyDefaultClientEnvMock} from '@github-ui/client-env/mock'
import {fixtureCleanup} from './browser-tests'
import {use as chaiUse} from 'chai'
import {chaiA11yAxe} from 'chai-a11y-axe'
import chaiDom from 'chai-dom'

// Register chai plugins
chaiUse(chaiA11yAxe)
chaiUse(chaiDom)

// Ensure that uncaught exceptions between tests result in the tests failing.
// This ensures we do not miss any errors, especially in our prod-smoke tests
let pendingError = null
let pendingErrorNotice = null

window.addEventListener('error', event => {
  pendingError = event.error
  pendingErrorNotice = 'An uncaught exception was thrown between tests'
})
window.addEventListener('unhandledrejection', async function (event) {
  if (event.promise) {
    try {
      await event.promise
    } catch (error) {
      // Ignore fetch responses modeled as exceptions.
      if (error && error.response instanceof Response) {
        return
      }

      pendingError = error
      pendingErrorNotice = `An uncaught promise rejection occurred between tests: ${event.reason}`
    }
  }
})

if (!document.getElementById('mocha')) {
  const mocha = document.createElement('div')
  mocha.id = 'mocha'
  document.body.appendChild(mocha)
}

const mochaFixture = document.createElement('div')
mochaFixture.id = 'mocha-fixture'
document.body.appendChild(mochaFixture)

afterEach(() => {
  fixtureCleanup()

  mochaFixture.textContent = ''
  if (pendingError) {
    console.error(pendingErrorNotice)
    throw pendingError
  }

  // Some of our code might set a beforeunload handler, which will block the test runner from exiting.
  window.onbeforeunload = undefined
})

globalThis.beforeEach = beforeEach

applyDefaultClientEnvMock()
