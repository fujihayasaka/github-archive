import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {JumpToElement} from '../jump-to-element'

describe('jump-to-element', () => {
  let container: JumpToElement

  beforeEach(async function () {
    container = await fixture(html`<jump-to></jump-to>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, JumpToElement)
  })
})
