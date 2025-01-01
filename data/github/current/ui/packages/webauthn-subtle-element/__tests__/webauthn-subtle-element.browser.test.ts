import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
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
