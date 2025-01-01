import {controller, target, targets} from '@github/catalyst'

@controller
export class LoadingContextElement extends HTMLElement {
  @target declare spinner: HTMLElement
  @target declare details: HTMLElement
  @targets declare fragments: HTMLElement[]

  #observer!: MutationObserver

  get hasLoadingFragments() {
    return (
      this.fragments
        .filter(fragment => !fragment.classList.contains('is-error'))
        .filter(fragment => fragment.hasAttribute('src')).length > 0
    )
  }

  connectedCallback() {
    if (!this.hasLoadingFragments) {
      return this.showDetails()
    }

    this.#observer = new MutationObserver(() => {
      if (!this.hasLoadingFragments) {
        this.showDetails()
        this.#observer.disconnect()
      }
    })

    this.#observer.observe(this.details, {childList: true, attributes: true, subtree: true})
  }

  private showDetails() {
    this.spinner.remove()
    this.details.toggleAttribute('hidden', false)
  }
}
