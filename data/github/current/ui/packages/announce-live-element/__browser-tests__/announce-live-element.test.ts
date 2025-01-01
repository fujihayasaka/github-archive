import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {AnnounceLiveElement} from '../announce-live-element'

describe('announce-live-element', () => {
  let container: AnnounceLiveElement

  beforeEach(async function () {
    container = await fixture(html`<announce-live></announce-live>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, AnnounceLiveElement)
  })
})
