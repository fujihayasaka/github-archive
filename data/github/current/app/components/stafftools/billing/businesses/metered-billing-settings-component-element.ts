import {controller, target} from '@github/catalyst'

@controller
class MeteredBillingSettingsComponentElement extends HTMLElement {
  @target declare meteredPlanCheckbox: HTMLInputElement
  @target declare meteredViaAzureCheckbox: HTMLInputElement
  @target declare azureSubscriptionIDContainer: HTMLElement
  @target declare meteredViaAzureCheckboxContainer: HTMLElement
  declare showAzureSubscriptionId: boolean

  handleMeteredViaAzureClick() {
    if (this.meteredPlanCheckbox?.checked) {
      this.meteredViaAzureCheckbox.checked = true
    }
    this.toggleAzureSubscriptionId()
  }

  toggleAzureSubscriptionId() {
    this.showAzureSubscriptionId = this.meteredPlanCheckbox?.checked || this.meteredViaAzureCheckbox?.checked
    this.renderOutput()
  }

  renderOutput = () => {
    this.azureSubscriptionIDContainer.hidden = !this.showAzureSubscriptionId
  }
}
