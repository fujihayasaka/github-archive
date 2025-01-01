import {controller, target} from '@github/catalyst'
import {parseHTML} from '@github-ui/parse-html'
import {verifiedFetch} from '@github-ui/verified-fetch'

// Controls individual user settings for copilot.
@controller
export class CopilotUserSettingsElement extends HTMLElement {
  @target declare form: HTMLFormElement
  @target declare overagesToggle: HTMLDetailsElement
  @target declare telemetry: HTMLInputElement
  @target declare snippy: HTMLDetailsElement
  @target declare achat: HTMLDetailsElement
  @target declare a_f: HTMLDetailsElement
  @target declare gchat: HTMLDetailsElement
  @target declare o1: HTMLDetailsElement
  @target declare o3: HTMLDetailsElement
  @target declare o_f: HTMLDetailsElement
  @target declare o_ff: HTMLDetailsElement
  @target declare overages: HTMLDetailsElement
  @target declare automatic_code_review: HTMLDetailsElement
  @target declare nextEditSuggestion: HTMLDetailsElement
  @target declare copilotPolicyBing: HTMLDetailsElement
  @target declare dashboardEntryPoint: HTMLDetailsElement
  @target declare defaultOrgCustomInstructions: HTMLDetailsElement
  @target declare billableCustomerMenu: HTMLDetailsElement
  @target declare submit: HTMLButtonElement

  #submitController!: AbortController | null
  #submitDashboardUpdateController!: AbortController | null

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

  get dashboardEntryPointPath(): string {
    return this.getAttribute('data-dashboard-entry-point-path') || ''
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
      this.nextEditSuggestion?.setAttribute('style', '')
      this.automatic_code_review?.setAttribute('style', '')
      this.achat?.setAttribute('style', '')
      this.a_f?.setAttribute('style', '')
      this.gchat?.setAttribute('style', '')
      this.o1?.setAttribute('style', '')
      this.o3?.setAttribute('style', '')
      this.o_ff?.setAttribute('style', '')
      this.o_f?.setAttribute('style', '')
      this.overages?.setAttribute('style', '')
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

    if (this.form.telemetry) formData.set('telemetry', this.form.telemetry.checked ? 'Allow' : '')

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
      this.showError()
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

  updateAFSetting(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.value

    if (!value) {
      return
    }

    this.form.a_f.value = value

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

  updateNextEditSuggestionSetting(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.value

    if (!value) {
      return
    }

    this.form.nextEditSuggestion.value = value

    this.handleSubmit()
  }

  updateAutomaticCodeReviewSetting(event: Event) {
    const hiddenInput = this.form.querySelector('input[name="automatic_code_review"]') as HTMLInputElement
    const button = (event.target as HTMLElement).closest('button')

    if (button?.value && hiddenInput) {
      hiddenInput.value = button.value
      this.handleSubmit()
    }
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

  updateO3Setting(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.value

    if (!value) {
      return
    }

    this.form.o3.value = value

    this.handleSubmit()
  }
  updateOFFSetting(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.value

    if (!value) {
      return
    }

    this.form.o_ff.value = value

    this.handleSubmit()
  }

  updateOFSetting(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.value

    if (!value) {
      return
    }

    this.form.o_f.value = value

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

  updateDefaultOrgCustomInstructions(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.getAttribute('data-value')

    if (!value) {
      return
    }

    this.form.default_org_custom_instructions.value = value

    this.handleSubmit()
  }

  updateDashboardEntryPointSetting(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.getAttribute('data-value')

    if (!value) {
      return
    }

    this.form.dashboard_entry_point.value = value

    this.submitDashboardEntryPointSetting()
  }

  async submitDashboardEntryPointSetting() {
    if (this.isSignup) {
      return
    }

    this.#submitDashboardUpdateController?.abort()
    this.#submitDashboardUpdateController = new AbortController()

    const {signal} = this.#submitDashboardUpdateController

    try {
      const formData = new FormData()
      formData.append('dashboard_entry_point', this.form.dashboard_entry_point.value)
      const res = await verifiedFetch(this.dashboardEntryPointPath, {
        method: 'PUT',
        body: formData,
        signal,
      })

      if (!res.ok) {
        this.showError()
        return
      }
    } catch {
      this.showError()
    }

    if (signal.aborted) {
      return
    }
  }

  updateOveragesSetting(event: Event) {
    if (this.overagesToggle.getAttribute('data-checked') === 'false') {
      this.form.overages.value = 'enabled'
    } else {
      this.form.overages.value = 'disabled'
    }
    event.preventDefault()
    this.handleSubmit()
  }

  updateBillableCustomer(event: Event) {
    event.preventDefault()
    const el = event.target as HTMLElement
    const value = el.closest('button')?.getAttribute('data-value')

    if (!value) {
      return
    }

    this.form.billable_customer.value = value
    this.handleSubmit()
  }

  updateSetting(event: Event) {
    const el = event.target as HTMLElement
    const value = el.closest('button')?.getAttribute('data-value')
    const listItem = el.closest('.ActionListItem')
    const policyName = listItem?.getAttribute('data-policy-name')

    if (!policyName || !value) {
      return
    }

    this.form[policyName].value = value

    this.handleSubmit()
  }

  showError() {
    const errorEl = this.querySelector('#cfi-error-text')
    if (errorEl) {
      errorEl.textContent = 'Something went wrong. Please try again.'
    }
  }
}
