import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
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
