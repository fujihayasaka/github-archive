import {beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {CopilotPurchaseIntentFormElement} from '../copilot-purchase-intent-form-element'

describe('copilot-purchase-intent-form-element', () => {
  let container: CopilotPurchaseIntentFormElement

  beforeEach(async function () {
    container = await fixture(html`
      <copilot-purchase-intent-form>
        <form action="/path" method="post" data-target="copilot-purchase-intent-form.form">
          <button type="submit" data-target="copilot-purchase-intent-form.formSubmitBtn">Submit</button>
        </form>
      </copilot-purchase-intent-form>
    `)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, CopilotPurchaseIntentFormElement)
  })
})
