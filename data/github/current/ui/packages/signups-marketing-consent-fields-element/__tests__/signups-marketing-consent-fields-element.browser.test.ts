import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {SignupsMarketingConsentFieldsElement} from '../signups-marketing-consent-fields-element'

describe('signups-marketing-consent-fields-element', () => {
  let container: SignupsMarketingConsentFieldsElement

  beforeEach(async function () {
    container = await fixture(
      html`<signups-marketing-consent-fields data-actor-country-code="US"></signups-marketing-consent-fields>`,
    )
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, SignupsMarketingConsentFieldsElement)
    assert.equal(container.actorCountryCode, 'US')
  })
})
