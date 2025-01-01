import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {TeamSyncOktaConfigFormElement} from '../team-sync-okta-config-form-element'

describe('team-sync-okta-config-form-element', () => {
  let container: TeamSyncOktaConfigFormElement

  beforeEach(async function () {
    container = await fixture(html`<team-sync-okta-config-form></team-sync-okta-config-form>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, TeamSyncOktaConfigFormElement)
  })
})
