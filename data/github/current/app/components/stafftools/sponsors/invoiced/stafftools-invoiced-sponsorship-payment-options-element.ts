import {controller, target} from '@github/catalyst'

@controller
class StafftoolsInvoicedSponsorshipPaymentOptionsElement extends HTMLElement {
  @target declare paymentOptions: HTMLElement

  showPaymentOptions() {
    this.paymentOptions.hidden = false
  }

  hidePaymentOptions() {
    this.paymentOptions.hidden = true
  }
}
