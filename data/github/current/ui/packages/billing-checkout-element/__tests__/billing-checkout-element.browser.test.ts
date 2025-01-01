import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {BillingCheckoutElement} from '../billing-checkout-element'

describe('billing-checkout-element', () => {
  let container: BillingCheckoutElement

  beforeEach(async function () {
    container = await fixture(html`<billing-checkout></billing-checkout>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, BillingCheckoutElement)
  })
})
