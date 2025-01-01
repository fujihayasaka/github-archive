import {controller, target} from '@github/catalyst'
import {parseHTML} from '@github-ui/parse-html'

// Controls individual user settings for copilot.
@controller
export class CopilotUserSettingsElement extends HTMLElement {
  @target form: HTMLFormElement
  @target telemetry: HTMLInputElement
  @target snippy: HTMLDetailsElement
  @target achat: HTMLDetailsElement
  @target gchat: HTMLDetailsElement
  @target o1: HTMLDetailsElement
  @target copilotPolicyBing: HTMLDetailsElement
  @target submit: HTMLButtonElement

  #submitController: AbortController | null

  static observedAttributes = ['data-enabled', 'data-onboarding']

  get enabled(): boolean {
    return this.getAttribute('data-enabled') === 'true'
  }

  set enabled(value: boolean) {
    this.setAttribute('data-enabled', String(value))
  }

  get isSignup(): boolean {
    return this.getAttribute('data-onboarding') === 'true'
  }

  set isSignup(value: boolean) {
    this.setAttribute('data-onboarding', String(value))
  }

  connectedCallback() {
    if (!this.hasAttribute('data-enabled')) {
      this.enabled = true
    }

    if (!this.hasAttribute('data-onboarding')) {
      this.isSignup = false
    }

    if (this.enabled) {
      this.snippy.setAttribute('style', '')
      this.copilotPolicyBing?.setAttribute('style', '')
      this.achat?.setAttribute('style', '')
      this.gchat?.setAttribute('style', '')
      this.o1?.setAttribute('style', '')
      this.telemetry.disabled = false
      if (this.submit) {
        this.submit.disabled = false
      }
    }
  }

  async handleSubmit() {
    if (this.isSignup) {
      return
    }

    this.#submitController?.abort()
    this.#submitController = new AbortController()

    const {signal} = this.#submitController
    const formData = new FormData(this.form)

    formData.set('telemetry', this.form.telemetry.checked ? 'Allow' : '')

    try {
      const res = await fetch(this.form.action, {
        method: 'PUT',
        body: formData,
        headers: {Accept: 'text/fragment+html'},
        signal,
      })

      const partial = parseHTML(document, await res.text())
      this.replaceWith(partial)
    } catch {
      const errorEl = this.querySelector('#cfi-error-text')

      if (errorEl) {
        errorEl.textContent = 'Something went wrong. Please try again.'
      }
    }

    if (signal.aborted) {
      return
    }
  }

  updateCodeSuggestionSetting(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.value

    if (!value) {
      return
    }

    this.form.public_code_suggestions.value = value

    this.handleSubmit()
  }

  updateAChatSetting(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.value

    if (!value) {
      return
    }

    this.form.a_chat.value = value

    this.handleSubmit()
  }

  updateGChatSetting(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.value

    if (!value) {
      return
    }

    this.form.g_chat.value = value

    this.handleSubmit()
  }

  updateO1Setting(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.value

    if (!value) {
      return
    }

    this.form.o1.value = value

    this.handleSubmit()
  }

  updateCopilotPolicyBing(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.value

    if (!value) {
      return
    }

    this.form.copilot_policy_bing.value = value

    this.handleSubmit()
  }
}
