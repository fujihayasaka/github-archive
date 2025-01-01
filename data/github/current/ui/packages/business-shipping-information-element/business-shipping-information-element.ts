import {controller, target} from '@github/catalyst'

@controller
export class BusinessShippingInformationElement extends HTMLElement {
  @target declare sameAsBillingCheckbox: HTMLInputElement | undefined
  @target declare sameAsBillingButtonGroup: HTMLDivElement | undefined
  @target declare sameAsBillingSubmitButton: HTMLButtonElement | undefined
  @target declare sameAsBillingCancelButton: HTMLButtonElement | undefined
  @target declare shippingInformationForm: HTMLFormElement | undefined
  @target declare editShippingInformationButton: HTMLButtonElement | undefined
  @target declare formContainer: HTMLDivElement | undefined
  @target declare detailsContainer: HTMLDivElement | undefined

  handleShippingInformationForm(event: Event) {
    const checkbox = event.currentTarget as HTMLInputElement

    if (this.sameAsBillingButtonGroup) {
      if (checkbox.checked) {
        // eslint-disable-next-line github/no-d-none
        this.sameAsBillingButtonGroup.classList.remove('d-none')
      } else {
        // eslint-disable-next-line github/no-d-none
        this.sameAsBillingButtonGroup.classList.add('d-none')
      }
    }

    if (this.sameAsBillingSubmitButton) this.sameAsBillingSubmitButton.hidden = !checkbox.checked
    if (this.sameAsBillingCancelButton) this.sameAsBillingCancelButton.hidden = !checkbox.checked
    if (this.shippingInformationForm) this.shippingInformationForm.hidden = checkbox.checked
  }

  showEditShippingInformationForm() {
    if (this.editShippingInformationButton) this.editShippingInformationButton.hidden = true
    if (this.formContainer) this.formContainer.hidden = false
    if (this.detailsContainer) this.detailsContainer.hidden = true
  }

  cancelShippingInformationEdit() {
    if (this.editShippingInformationButton) this.editShippingInformationButton.hidden = false
    if (this.sameAsBillingCheckbox) this.sameAsBillingCheckbox.checked = false
    if (this.shippingInformationForm) this.shippingInformationForm.hidden = false
    if (this.sameAsBillingSubmitButton) this.sameAsBillingSubmitButton.hidden = true
    if (this.sameAsBillingCancelButton) this.sameAsBillingCancelButton.hidden = true
    if (this.formContainer) this.formContainer.hidden = true
    if (this.detailsContainer) this.detailsContainer.hidden = false
  }
}
