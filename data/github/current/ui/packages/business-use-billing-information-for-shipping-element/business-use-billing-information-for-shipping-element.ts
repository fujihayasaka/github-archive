import {controller, target} from '@github/catalyst'

@controller
export class BusinessUseBillingInformationForShippingElement extends HTMLElement {
  @target declare submitButton: HTMLButtonElement | undefined
  @target declare shippingInformationForm: HTMLButtonElement | undefined

  handleShippingInformationForm(event: Event) {
    const checkbox = event.currentTarget as HTMLInputElement

    if (this.submitButton) {
      this.submitButton.hidden = !checkbox.checked
    }

    if (this.shippingInformationForm) {
      this.shippingInformationForm.hidden = checkbox.checked
    }
  }
}
