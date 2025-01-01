import {assert, fixture, html, setup, suite, test} from '@github-ui/browser-tests'
import {MarketplaceSecurityComplianceTraderSelfCertificationElement} from '../marketplace-security-compliance-trader-self-certification-element'

suite('marketplace-security-compliance-trader-self-certification-element', () => {
  let container: MarketplaceSecurityComplianceTraderSelfCertificationElement

  setup(async function () {
    container = await fixture(
      html`<marketplace-security-compliance-trader-self-certification></marketplace-security-compliance-trader-self-certification>`,
    )
  })

  test('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, MarketplaceSecurityComplianceTraderSelfCertificationElement)
  })
})
