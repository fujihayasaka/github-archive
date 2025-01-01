import {afterEach, beforeEach, describe, it, assert, fixture, html} from '../browser-tests'

describe('Browser Tests Utils', () => {
  let setupCounter = 0
  let teardownCounter = 0

  beforeEach(() => {
    setupCounter++
  })

  afterEach(() => {
    teardownCounter++
  })

  it('globals are available', () => {
    assert.isDefined(describe)
    assert.isDefined(beforeEach)
    assert.isDefined(afterEach)
    assert.isDefined(it)
    assert.isDefined(fixture)
    assert.isDefined(html)
  })

  it('setup and teardown work', () => {
    assert.equal(setupCounter, 2)
    assert.equal(teardownCounter, 1)
  })
})
