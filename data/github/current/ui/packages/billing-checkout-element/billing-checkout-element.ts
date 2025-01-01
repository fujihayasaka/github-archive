import {attr, controller, target, targets} from '@github/catalyst'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {sendEvent} from '@github-ui/hydro-analytics'
import {trackPurchaseEvent, trackTrialEvent} from '@github-ui/microsoft-analytics/events'
import {PageActionPeriodType} from '@github-ui/microsoft-analytics'

@controller
export class BillingCheckoutElement extends HTMLElement {
  @attr declare trialAllowed: string
  @attr declare paymentPeriod: string

  @target declare submitButton: HTMLButtonElement
  @targets declare editButtons: HTMLButtonElement[]
  @target declare billingFrequencySummary: HTMLButtonElement
  @target declare billingFrequencyForm: HTMLButtonElement
  @target declare premiumRequestsSummary: HTMLButtonElement
  @target declare premiumRequestsForm: HTMLButtonElement
  @target declare billingInformationWrapper: HTMLButtonElement

  handleSubscriptionActivation() {
    const isTrialAllowed = this.trialAllowed === 'true'
    const isProPlusSignup = this.getAttribute('data-pro-plus') === 'true'
    if (isProPlusSignup) {
      copilotLocalStorage.setProPlusSuccessBannerFlag(true)
      copilotLocalStorage.setProPlusAnimationFlag(true)
      // Send Pro+ purchase to MSFT analytics
      trackPurchaseEvent({
        orderId: crypto.randomUUID(),
        productTitle: 'GitHub Copilot Pro Plus Purchase',
        seats: 1,
        periodType: this.paymentPeriod === 'monthly' ? PageActionPeriodType.Month : PageActionPeriodType.Year,
      })
    }

    if (isTrialAllowed) {
      copilotLocalStorage.setTrialSuccessBannerFlag(true)
      // Send trial purchase to MSFT analytics
      trackTrialEvent({
        orderId: crypto.randomUUID(),
        productTitle: 'GitHub Copilot Pro Trial',
        seats: 1,
        periodType: this.paymentPeriod === 'monthly' ? PageActionPeriodType.Month : PageActionPeriodType.Year,
      })
    }

    sendEvent('dotcom_chat.activate', {
      target: isTrialAllowed
        ? 'PRO_TRIAL_ACTIVATION_SUCCESS'
        : isProPlusSignup
          ? 'PRO_PLUS_ACTIVATION_SUCCESS'
          : 'PRO_ACTIVATION_SUCCESS',
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

  hidePremiumRequestsForm() {
    this.premiumRequestsSummary.hidden = false
    this.premiumRequestsForm.hidden = true
  }

  showPremiumRequestsForm() {
    this.premiumRequestsSummary.hidden = true
    this.premiumRequestsForm.hidden = false
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

  editPremiumRequests() {
    this.showPremiumRequestsForm()
    this.hideBillingInformation()

    this.hideEditButtons()
    this.hideSubmitButton()
  }

  cancelEditPremiumRequests() {
    this.hidePremiumRequestsForm()
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
