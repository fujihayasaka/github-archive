import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {FullstoryCaptureElement} from '../fullstory-capture-element'

describe('fullstory-capture-element', () => {
  let container: FullstoryCaptureElement

  beforeEach(async function () {
    container = await fixture(html`<fullstory-capture></fullstory-capture>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, FullstoryCaptureElement)
  })
})
