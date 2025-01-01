import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {WebauthnSubtleElement} from '../webauthn-subtle-element'

describe('webauthn-subtle-element', () => {
  let container: WebauthnSubtleElement

  beforeEach(async function () {
    container = await fixture(html`<webauthn-subtle></webauthn-subtle>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, WebauthnSubtleElement)
  })
})
