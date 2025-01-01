import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {SecurityAnalysisDependabotUpdatesElement} from '../security-analysis-dependabot-updates-element'

describe('security-analysis-dependabot-updates-element', () => {
  let container: SecurityAnalysisDependabotUpdatesElement

  beforeEach(async function () {
    container = await fixture(html`<security-analysis-dependabot-updates></security-analysis-dependabot-updates>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, SecurityAnalysisDependabotUpdatesElement)
  })
})
