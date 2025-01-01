import {controller, target} from '@github/catalyst'
import type {SelectPanelExperimentalElement} from '../../../app/components/primer/experimental/select-panel-element'

const CAPTURE_ACCOUNT_NAME_RE = /^[^\n]*/

@controller
export class CopilotPlanAccountSelectElement extends HTMLElement {
  @target declare panel: SelectPanelExperimentalElement

  connectedCallback() {
    this.panel.filterFn = this.#filter
    this.panel.addEventListener('itemActivated', this.#handleItemSelect)
  }

  disconnectedCallback() {
    this.panel.removeEventListener('itemActivated', this.#handleItemSelect)
  }

  #filter = (item: HTMLElement, query: string) => {
    if (!query) {
      return true
    }

    const accountName = item.textContent?.trim()
    const match = accountName?.match(CAPTURE_ACCOUNT_NAME_RE)

    if (match) {
      return match[0].toLowerCase().includes(query.toLowerCase())
    }

    return false
    // return true if the item should be displayed, false otherwise
  }

  #handleItemSelect = (event: CustomEvent) => {
    const selected = event.detail.item

    if (!selected) {
      // shouldn't happen, but let's be safe
      return
    }

    const name = selected.getAttribute('data-name')
    const accountType = selected.getAttribute('data-type').toLowerCase()

    window.location.href = `/github-copilot/purchase?${accountType}=${name}`
  }
}
