import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {CopilotMixedLicenseOrgsListElement} from '../copilot-mixed-license-orgs-list-element'

describe('copilot-mixed-license-orgs-list-element', () => {
  let container: CopilotMixedLicenseOrgsListElement

  beforeEach(async function () {
    container = await fixture(html`<copilot-mixed-license-orgs-list></copilot-mixed-license-orgs-list>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, CopilotMixedLicenseOrgsListElement)
  })
})
