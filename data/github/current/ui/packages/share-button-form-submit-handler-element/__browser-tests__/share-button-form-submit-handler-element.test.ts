import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {ShareButtonTextHandlerElement} from '../share-button-form-submit-handler-element'

describe('share-button-text-handler-element', () => {
  let container: ShareButtonTextHandlerElement

  beforeEach(async function () {
    container = await fixture(html`
      <share-button-text-handler>
        <input value="Sponsor me!" data-target="share-button-text-handler.share_text" />
        <input value="" data-targets="share-button-text-handler.text" />
      </share-button-text-handler>
    `)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, ShareButtonTextHandlerElement)
  })

  it('share text is added to text input', () => {
    container.updateText()
    const text = container.text[0]
    assert(text)
    assert.equal(text.value, 'Sponsor me!')
  })
})
