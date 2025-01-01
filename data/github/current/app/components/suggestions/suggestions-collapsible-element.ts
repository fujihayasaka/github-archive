import {attr, controller, target} from '@github/catalyst'

@controller
class SuggestionsCollapsibleElement extends HTMLElement {
  @attr open = false
  @target declare openButton: HTMLButtonElement
  @target declare collapseButton: HTMLButtonElement
  @target declare body: HTMLElement

  connectedCallback() {
    this.#updateVisibility()
  }

  toggle() {
    this.open = !this.open
    this.#updateVisibility()
  }

  #updateVisibility() {
    this.openButton.style.display = this.open ? 'none' : ''
    this.collapseButton.style.display = this.open ? '' : 'none'
    this.body.style.display = this.open ? '' : 'none'
  }
}
