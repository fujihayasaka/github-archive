import {doNotTrack} from '@github-ui/do-not-track'
import {trackBuyIntentEvent} from '@github-ui/microsoft-analytics/events'
import {attr, controller, target} from '@github/catalyst'

@controller
export class CopilotPurchaseIntentFormElement extends HTMLElement {
  @target declare formSubmitBtn: HTMLButtonElement
  @target declare form: HTMLFormElement
  @attr accountType = ''
  private submitting = false

  connectedCallback() {
    this.formSubmitBtn.addEventListener('click', this.handleSubmit)
  }

  disconnectedCallback() {
    this.formSubmitBtn.removeEventListener('click', this.handleSubmit)
  }

  handleSubmit = async (event: Event) => {
    event.preventDefault()

    if (this.submitting) return

    this.submitting = true
    this.formSubmitBtn.disabled = true

    /**
     * Because we want to await analytics submission before submitting the form,
     * we need to check if the user has explicitly disabled tracking. This ensures
     * we avoid an unecessary delay in form submission.
     */
    if (doNotTrack()) {
      this.form.submit()
      return
    }

    try {
      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error('MSFT analytics tracking timeout')), 1000),
      )
      await Promise.race([
        trackBuyIntentEvent({
          id: 'GitHub_CopilotEnablePurchase',
          contentName: this.getPlanString(),
        }),
        timeoutPromise,
      ])
      // eslint-disable-next-line unused-imports/no-unused-vars
    } catch (_) {
      // ignore error
    } finally {
      this.form.submit()
    }
  }

  private getPlanString() {
    return this.accountType === 'Organization' ? 'Copilot Business' : 'Copilot Business / Copilot Enterprise'
  }
}
