import {controller, target} from '@github/catalyst'

@controller
export class EMUContributionBlockedHintElement extends HTMLElement {
  @target declare popoverElem: HTMLElement
  @target declare returnToElem: HTMLInputElement

  connectedCallback() {
    if (this.returnToElem && this.returnToElem.value && window.location.hash) {
      this.returnToElem.value += window.location.hash
    }
  }

  handlePopoverToggle() {
    if (this.popoverElem) {
      this.popoverElem.hidden = !this.popoverElem.hidden
    }
  }
}
