import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
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
