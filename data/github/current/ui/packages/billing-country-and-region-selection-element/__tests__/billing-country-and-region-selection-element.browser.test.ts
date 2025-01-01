import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {BillingCountryAndRegionSelectionElement} from '../billing-country-and-region-selection-element'

describe('billing-country-and-region-selection-element', () => {
  let container: BillingCountryAndRegionSelectionElement

  beforeEach(async function () {
    container = await fixture(html`<billing-country-and-region-selection></billing-country-and-region-selection>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, BillingCountryAndRegionSelectionElement)
  })
})
