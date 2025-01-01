import {assert, fixture, html} from '@github-ui/tests/browser'
import {beforeEach, describe, it} from '@github-ui/tests'
import {ContextRegionElement} from '../context-region-element'

describe('context-region-element', () => {
  let container: ContextRegionElement

  beforeEach(async function () {
    container = await fixture(html`<context-region></context-region>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, ContextRegionElement)
  })
})
