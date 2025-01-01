import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {BusinessShippingInformationElement} from '../business-shipping-information-element'

describe('business-shipping-information-element', () => {
  let container: BusinessShippingInformationElement

  beforeEach(async function () {
    container = await fixture(html`<business-shipping-information></business-shipping-information>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, BusinessShippingInformationElement)
  })
})
