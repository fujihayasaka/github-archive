import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {BusinessTrialAccountsFormElement} from '../business-trial-accounts-form-element'

describe('business-trial-accounts-form-element', () => {
  let container: BusinessTrialAccountsFormElement

  beforeEach(async function () {
    container = await fixture(html`<business-trial-accounts-form></business-trial-accounts-form>`)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, BusinessTrialAccountsFormElement)
  })
})
