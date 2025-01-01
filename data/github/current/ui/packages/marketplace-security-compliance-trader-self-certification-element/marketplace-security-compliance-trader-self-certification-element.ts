import {controller, target} from '@github/catalyst'

@controller
export class MarketplaceSecurityComplianceTraderSelfCertificationElement extends HTMLElement {
  @target traderInputs: HTMLElement | undefined
  @target traderIdType: HTMLSelectElement | undefined
  @target traderIdOtherInput: HTMLDivElement | undefined

  renderTraderInputs() {
    const selfCertificationInput: HTMLInputElement | null = document.querySelector(
      'input[name="marketplace_listing[trader_self_certification]"]:checked',
    )
    if (!selfCertificationInput || !this.traderInputs) return

    const selectedValue = selfCertificationInput.value
    if (selectedValue === 'trader') {
      this.traderInputs.style.display = 'block'
    } else {
      this.traderInputs.style.display = 'none'
    }
  }

  renderTraderIdInput() {
    if (!this.traderIdType || !this.traderIdOtherInput) return

    const selectedValue = this.traderIdType.value
    if (selectedValue === 'other') {
      this.traderIdOtherInput.style.display = 'block'
    } else {
      this.traderIdOtherInput.style.display = 'none'
    }
  }
}
