import { controller, target, targets } from '@github/catalyst'

@controller
export class FormTableSuggestionsElement extends HTMLElement {
  @target body: HTMLElement
  @target heading: HTMLElement
  @targets rows: FormTableSuggestionsRowElement[]

  connectedCallback() {
    if (!this.hasAttribute('data-read-only')) {
      this.updateVisibility()
    }
  }

  // Only show the suggestions section when there are pending predictions
  updateVisibility() {
    const visibleRows = this.rows.filter((row) => {
      return !row.hidden
    })

    this.heading.hidden = !visibleRows.length
    this.body.hidden = !visibleRows.length
  }

  // Handle the edge case where a prediction is accepted but then the cloned
  // row is deleted (aka withdrawn) before the form is submitted.
  rejectWithdrawnClone(event: CustomEvent) {
    const cloneIndex = event.detail.index
    if (!cloneIndex) return

    const sourceRow = this.rows.find((element) => {
      return element.cloneIndexElement.value === cloneIndex
    })
    if (sourceRow) sourceRow.reject()
  }
}

@controller
export class FormTableSuggestionsRowElement extends HTMLElement {
  @target cloneIndexElement: HTMLInputElement
  @target decision: HTMLInputElement
  @targets inputs: HTMLInputElement[]

  accept() {
    this.decision.value = 'accepted'
    this.hidden = true
    this.dispatchEvent(new CustomEvent('acceptRow', { detail: this }))
  }

  reject() {
    this.decision.value = 'rejected'
    this.hidden = true
    this.dispatchEvent(new CustomEvent('rejectRow', { detail: this }))
  }

  updateVulnerabilityIndex(event: CustomEvent) {
    this.cloneIndexElement.value = event.detail.index
  }
}
