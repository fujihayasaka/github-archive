// This is a barrel file that re-exports all testing utilities that require a browser environment
export {
  assert,
  fixture,
  fixtureCleanup,
  html,
  waitUntil,
  aTimeout,
  nextFrame,
  elementUpdated,
  chai,
} from '@open-wc/testing'
export {spread} from '@open-wc/lit-helpers'
export {userEvent, page} from '@vitest/browser/context'
