import type {TestAPI} from 'vitest'

export {
  assert,
  expect,
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

let testHelpers

if (process.env.TEST_RUNNER === 'vitest') {
  testHelpers = (await import('./vitest-exports')).default
} else {
  testHelpers = (await import('./mocha-exports')).default
}

const describe = testHelpers.describe as Mocha.SuiteFunction
const _it = testHelpers.it
const it = testHelpers.it as Mocha.TestFunction
const beforeEach = testHelpers.beforeEach as Mocha.HookFunction
const beforeAll = testHelpers.beforeAll as Mocha.HookFunction
const afterEach = testHelpers.afterEach as Mocha.HookFunction
const afterAll = testHelpers.afterAll as Mocha.HookFunction

function itWithTimeout(title: string, fn: () => void, timeout?: number) {
  if (process.env.TEST_RUNNER === 'vitest') {
    return (_it as TestAPI)(title, fn, typeof timeout === 'number' ? timeout : undefined)
  } else {
    return (_it as Mocha.TestFunction)(title, function (this: Mocha.Context) {
      if (timeout) {
        this.timeout(timeout)
      }
      return fn()
    })
  }
}

export {describe, it, itWithTimeout, beforeEach, beforeAll, afterEach, afterAll}
