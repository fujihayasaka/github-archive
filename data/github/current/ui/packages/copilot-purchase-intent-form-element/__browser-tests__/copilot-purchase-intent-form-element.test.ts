import {assert, fixture, html, setup, suite, test} from '@github-ui/browser-tests'
import {CopilotPurchaseIntentFormElement} from '../copilot-purchase-intent-form-element'

suite('copilot-purchase-intent-form-element', () => {
  let container: CopilotPurchaseIntentFormElement

  setup(async function () {
    container = await fixture(html`
      <copilot-purchase-intent-form>
        <form action="/path" method="post" data-target="copilot-purchase-intent-form.form">
          <button type="submit" data-target="copilot-purchase-intent-form.formSubmitBtn">Submit</button>
        </form>
      </copilot-purchase-intent-form>
    `)
  })

  test('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, CopilotPurchaseIntentFormElement)
  })
})
