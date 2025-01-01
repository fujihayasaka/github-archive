import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {BusinessUseBillingInformationForShippingElement} from '../business-use-billing-information-for-shipping-element'

describe('business-use-billing-information-for-shipping-element', () => {
  let container: BusinessUseBillingInformationForShippingElement

  beforeEach(async function () {
    container = await fixture(
      html`<business-use-billing-information-for-shipping></business-use-billing-information-for-shipping>`,
    )
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, BusinessUseBillingInformationForShippingElement)
  })
})
