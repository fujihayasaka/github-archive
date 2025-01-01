import {beforeEach, describe, it, assert, fixture, html} from '@github-ui/browser-tests'
import {CopilotReviewFeedbackElement} from '../copilot-review-feedback-element'

describe('copilot-review-feedback-element', () => {
  let container: CopilotReviewFeedbackElement

  beforeEach(async function () {
    container = await fixture(html`
      <copilot-review-feedback>
        <div data-target="copilot-review-feedback.voteUpButton"></div>
        <div data-target="copilot-review-feedback.voteDownButton"></div>
        <div data-target="copilot-review-feedback.feedbackCheckboxes"></div>
        <div data-target="copilot-review-feedback.submitButton"></div>
        <div data-target="copilot-review-feedback.form"></div>
      </copilot-review-feedback>
    `)
  })

  it('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, CopilotReviewFeedbackElement)
  })
})
