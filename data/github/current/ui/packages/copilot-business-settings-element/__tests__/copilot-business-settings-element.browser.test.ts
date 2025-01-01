import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {CopilotBusinessSettingsElement} from '../copilot-business-settings-element'

describe('copilot-business-settings-element', () => {
  let container: CopilotBusinessSettingsElement

  beforeEach(async function () {
    container = await fixture(html`<copilot-business-settings></copilot-business-settings>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, CopilotBusinessSettingsElement)
  })
})
