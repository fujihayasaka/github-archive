import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {UnveilContainerElement} from '../unveil-container-element'

describe('unveil-container-element', () => {
  let container: UnveilContainerElement

  beforeEach(async function () {
    container = await fixture(html`<unveil-container></unveil-container>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, UnveilContainerElement)
  })
})
