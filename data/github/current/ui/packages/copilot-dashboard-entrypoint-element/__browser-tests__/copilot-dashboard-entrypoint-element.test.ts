import {assert, fixture, html, setup, suite, test} from '@github-ui/browser-tests'
import {CopilotDashboardEntrypointElement} from '../copilot-dashboard-entrypoint-element'

suite('copilot-dashboard-entrypoint-element', () => {
  let container: CopilotDashboardEntrypointElement

  setup(async function () {
    container = await fixture(html`
      <copilot-dashboard-entrypoint data-controller="copilot-dashboard-entrypoint">
        <div class="copilotPreview">
          <label class="sr-only" for="copilot-dashboard-entrypoint-textarea">Ask a question</label>
          <textarea
            id="copilot-dashboard-entrypoint-textarea"
            data-target="copilot-dashboard-entrypoint.textarea"
            class="copilotPreview__input"
            placeholder="Ask a question"
            rows="1"
            autofocus
          ></textarea>
          <div class="copilotPreview__trailingItems">
            <a
              href="https://github.com/copilot"
              class="copilotPreview__copilotButton"
              data-target="copilot-dashboard-entrypoint.copilot_button"
            ></a>
            <button aria-label="Send" data-target="copilot-dashboard-entrypoint.send_button"></button>
          </div>
        </div>

        <div class="copilotPreview__footer" data-target="copilot-dashboard-entrypoint.footer">
          <ul class="copilotPreview__suggestions" data-target="copilot-dashboard-entrypoint.suggestions"></ul>

          <div class="copilotPreview__disclaimer" data-target="copilot-dashboard-entrypoint.disclaimer"></div>
        </div>
      </copilot-dashboard-entrypoint>
    `)
  })

  test('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, CopilotDashboardEntrypointElement)
  })
})
