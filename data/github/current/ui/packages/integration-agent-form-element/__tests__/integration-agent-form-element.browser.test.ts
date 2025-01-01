import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {IntegrationAgentFormElement} from '../integration-agent-form-element'

describe('integration-agent-form-element', () => {
  let container: IntegrationAgentFormElement

  beforeEach(async function () {
    container = await fixture(html`<integration-agent-form></integration-agent-form>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, IntegrationAgentFormElement)
  })
})
