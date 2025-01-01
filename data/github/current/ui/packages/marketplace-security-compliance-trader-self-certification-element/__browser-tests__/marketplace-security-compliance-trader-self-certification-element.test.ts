import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {MarketplaceSecurityComplianceTraderSelfCertificationElement} from '../marketplace-security-compliance-trader-self-certification-element'

describe('marketplace-security-compliance-trader-self-certification-element', () => {
  let container: MarketplaceSecurityComplianceTraderSelfCertificationElement

  beforeEach(async function () {
    container = await fixture(
      html`<marketplace-security-compliance-trader-self-certification></marketplace-security-compliance-trader-self-certification>`,
    )
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, MarketplaceSecurityComplianceTraderSelfCertificationElement)
  })
})
