import {controller, target} from '@github/catalyst'
import {requestSubmit} from '@github-ui/form-utils'

@controller
export class CopilotReviewFeedbackElement extends HTMLElement {
  @target declare voteUpButton: HTMLButtonElement
  @target declare voteDownButton: HTMLButtonElement
  @target declare feedbackCheckboxes: HTMLElement
  @target declare submitButton: HTMLButtonElement
  @target declare positiveForm: HTMLFormElement
  @target declare negativeForm: HTMLFormElement

  connectedCallback() {
    this.validateAnySelected()
    this.hideErrorText()
  }

  positiveFeedback() {
    requestSubmit(this.positiveForm)
    this.voteUpButton.disabled = true
    this.voteDownButton.hidden = true
  }

  validateAnySelected() {
    const checkedList = this.feedbackCheckboxes.querySelectorAll('input:checked')

    if (checkedList.length === 0) {
      this.showErrorText()
      return false
    } else {
      this.hideErrorText()
      return true
    }
  }

  showErrorText() {
    this.submitButton.disabled = true
    this.feedbackCheckboxes.classList.remove('mb-5')

    const nextElement = this.feedbackCheckboxes.nextElementSibling as HTMLElement
    if (nextElement) {
      nextElement.hidden = false
    }
  }

  hideErrorText() {
    this.submitButton.disabled = false
    this.feedbackCheckboxes.classList.add('mb-5')

    const nextElement = this.feedbackCheckboxes.nextElementSibling as HTMLElement
    if (nextElement) {
      nextElement.hidden = true
    }
  }

  negativeFeedback(event: Event) {
    event.preventDefault()
    if (this.validateAnySelected()) {
      this.voteDownButton.disabled = true
      this.voteUpButton.hidden = true

      const closeButton = this.negativeForm.querySelector('button[aria-label="Close"]') as HTMLElement
      if (closeButton) closeButton.click()
      requestSubmit(this.negativeForm)
    }
  }
}
