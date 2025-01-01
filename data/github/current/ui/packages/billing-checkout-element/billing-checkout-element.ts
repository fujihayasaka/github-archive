import {attr, controller, target, targets} from '@github/catalyst'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {sendEvent} from '@github-ui/hydro-analytics'

@controller
export class BillingCheckoutElement extends HTMLElement {
  @attr declare trialAllowed: string
  @target declare submitButton: HTMLButtonElement
  @targets declare editButtons: HTMLButtonElement[]
  @target declare billingFrequencySummary: HTMLButtonElement
  @target declare billingFrequencyForm: HTMLButtonElement
  @target declare billingInformationWrapper: HTMLButtonElement

  handleSubscriptionActivation() {
    const isTrialAllowed = this.trialAllowed === 'true'

    if (isTrialAllowed) {
      copilotLocalStorage.setTrialSuccessBannerFlag(true)
    }

    sendEvent('dotcom_chat.activate', {
      target: isTrialAllowed ? 'PRO_TRIAL_ACTIVATION_SUCCESS' : 'PRO_ACTIVATION_SUCCESS',
      mode: 'immersive',
    })
  }

  hideSubmitButton() {
    if (this.submitButton) {
      this.submitButton.hidden = true
    }
  }

  showSubmitButton() {
    if (this.submitButton) {
      this.submitButton.hidden = false
    }
  }

  hideEditButtons() {
    for (const button of this.editButtons) {
      button.hidden = true
    }
  }

  showEditButtons() {
    for (const button of this.editButtons) {
      button.hidden = false
    }
  }

  hideBillingFrequencyForm() {
    this.billingFrequencySummary.hidden = false
    this.billingFrequencyForm.hidden = true
  }

  showBillingFrequencyForm() {
    this.billingFrequencySummary.hidden = true
    this.billingFrequencyForm.hidden = false
  }

  hideBillingInformation() {
    if (this.billingInformationWrapper) {
      this.billingInformationWrapper.hidden = true
    }
  }

  showBillingInformation() {
    if (this.billingInformationWrapper) {
      this.billingInformationWrapper.hidden = false
    }
  }

  editBillingFrequency() {
    this.showBillingFrequencyForm()
    this.hideBillingInformation()

    this.hideEditButtons()
    this.hideSubmitButton()
  }

  cancelEditBillingFrequency() {
    this.hideBillingFrequencyForm()
    this.showBillingInformation()

    this.showEditButtons()
    this.showSubmitButton()
  }

  editBillingInformation() {
    this.hideEditButtons()
    this.hideSubmitButton()
  }

  cancelEditBillingInformation() {
    this.showEditButtons()
    this.showSubmitButton()
  }

  editPaymentMethod() {
    this.hideEditButtons()
    this.hideSubmitButton()
  }

  cancelEditPaymentMethod() {
    this.showEditButtons()
    this.showSubmitButton()
  }
}
