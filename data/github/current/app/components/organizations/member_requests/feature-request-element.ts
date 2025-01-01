import {attr, controller, target} from '@github/catalyst'
import {getBaseFetchHeaders} from '@github-ui/fetch-headers'

@controller
class FeatureRequestElement extends HTMLElement {
  @attr declare actionPath: string
  @attr declare featureName: string

  @target declare csrfTokenRequest: HTMLFormElement
  @target declare csrfTokenCancel: HTMLFormElement
  @target declare prompt: HTMLElement
  @target declare requestButton: HTMLButtonElement
  @target declare cancelButton: HTMLButtonElement
  @target declare success: HTMLElement

  originalText = new WeakMap()

  async submit() {
    let response
    try {
      this.disableButton(this.requestButton, 'Requesting...')
      const data = new FormData()
      data.append('feature', this.featureName)

      response = await fetch(this.actionPath, {
        method: 'POST',
        body: data,
        headers: {
          Accept: 'application/json',
          ...getBaseFetchHeaders(),
          'Scoped-CSRF-Token': this.csrfTokenRequest.value,
        },
      })
    } catch {
      // Show error
      return
    } finally {
      this.revertButton(this.requestButton)
    }
    if (response && !response.ok) {
      // Show error
    } else {
      this.prompt.hidden = true
      this.success.hidden = false
    }
  }

  async cancel() {
    let response
    try {
      this.disableButton(this.cancelButton, 'Cancelling...')
      const data = new FormData()
      data.append('feature', this.featureName)

      response = await fetch(this.actionPath, {
        method: 'DELETE',
        body: data,
        headers: {
          Accept: 'application/json',
          ...getBaseFetchHeaders(),
          'Scoped-CSRF-Token': this.csrfTokenCancel.value,
        },
      })
    } catch {
      // Show error
      return
    } finally {
      this.revertButton(this.cancelButton)
    }
    if (response && !response.ok) {
      // Show error
    } else {
      this.prompt.hidden = false
      this.success.hidden = true
    }
  }

  disableButton(button: HTMLButtonElement, disabledText: string) {
    this.originalText.set(button, button.innerHTML)
    // The first click event is not propagated if text content is changed.
    // This was preventing hydro event from being fired properly.
    setTimeout(() => {
      button.textContent = disabledText
    }, 0)
    button.disabled = true
  }

  revertButton(button: HTMLButtonElement) {
    const text = this.originalText.get(button)
    if (text != null) {
      button.innerHTML = text
      button.disabled = false
      this.originalText.delete(button)
    }
  }
}
