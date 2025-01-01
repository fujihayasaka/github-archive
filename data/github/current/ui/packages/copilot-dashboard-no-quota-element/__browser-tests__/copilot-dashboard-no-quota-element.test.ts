import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {CopilotDashboardNoQuotaElement} from '../copilot-dashboard-no-quota-element'

describe('copilot-dashboard-no-quota-element', () => {
  let container: CopilotDashboardNoQuotaElement

  beforeEach(async function () {
    container = await fixture(html`<copilot-dashboard-no-quota></copilot-dashboard-no-quota>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, CopilotDashboardNoQuotaElement)
  })
})
