import {controller, target} from '@github/catalyst'

@controller
export class MarketplaceSecurityComplianceTraderSelfCertificationElement extends HTMLElement {
  @target declare traderInputs: HTMLElement | undefined
  @target declare traderIdType: HTMLSelectElement | undefined
  @target declare traderIdOtherInput: HTMLDivElement | undefined
  @target declare repoPublicInput: HTMLInputElement | undefined
  @target declare repoUrlInput: HTMLDivElement | undefined

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

  renderRepoUrlInputs() {
    if (!this.repoPublicInput || !this.repoUrlInput) return

    if (this.repoPublicInput.checked) {
      this.repoUrlInput.style.display = 'block'
    } else {
      this.repoUrlInput.style.display = 'none'
    }
  }
}
