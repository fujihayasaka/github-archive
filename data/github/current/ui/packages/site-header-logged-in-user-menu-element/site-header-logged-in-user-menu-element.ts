import {controller, target} from '@github/catalyst'

@controller
export class SiteHeaderLoggedInUserMenuElement extends HTMLElement {
  @target declare popoverElem: HTMLElement
  @target declare returnToElem: HTMLInputElement
  @target declare detailsElem: HTMLDetailsElement

  connectedCallback() {
    if (this.returnToElem && this.returnToElem.value && window.location.hash) {
      this.returnToElem.value += window.location.hash
    }

    if (!this.popoverElem) return
    this.popoverElem.hidden = false

    if (!this.detailsElem) return
    this.detailsElem.addEventListener('toggle', () => this.handleDetailsToggle())
  }

  handleDetailsToggle() {
    this.popoverElem.hidden = this.detailsElem.open ? true : false
  }
}
