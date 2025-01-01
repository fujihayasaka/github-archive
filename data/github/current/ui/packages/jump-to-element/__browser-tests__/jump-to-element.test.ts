import {assert, fixture, html, setup, suite, test} from '@github-ui/browser-tests'
import {JumpToElement} from '../jump-to-element'

suite('jump-to-element', () => {
  let container: JumpToElement

  setup(async function () {
    container = await fixture(html`<jump-to></jump-to>`)
  })

  test('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, JumpToElement)
  })
})
