import {afterEach} from 'vitest'

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

afterEach(() => {
  if (pendingError) {
    console.error(pendingErrorNotice)
    throw pendingError
  }
})
