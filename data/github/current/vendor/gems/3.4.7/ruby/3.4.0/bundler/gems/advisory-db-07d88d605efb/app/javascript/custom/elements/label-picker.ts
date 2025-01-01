import { controller, target, targets } from '@github/catalyst'

@controller
export class LabelPickerElement extends HTMLElement {
  originalLabelIds: string[]

  @target form: HTMLFormElement
  @targets labels: HTMLLabelElement[]

  toggleLabel(event: PointerEvent) {
    const label = event.currentTarget! as HTMLLabelElement
    const checkbox = label.querySelector('input') as HTMLInputElement
    const checkmark = label.querySelector('.octicon-check') as HTMLElement

    if (checkbox.checked) {
      label.setAttribute('aria-checked', 'false')
      checkbox.checked = false
      checkmark.classList.remove('v-visible')
      checkmark.classList.add('v-hidden')
    } else {
      label.setAttribute('aria-checked', 'true')
      checkbox.checked = true
      checkmark.classList.add('v-visible')
      checkmark.classList.remove('v-hidden')
    }
  }

  toggleOverlay(event: ToggleEvent) {
    const overlay = event.currentTarget! as HTMLDetailsElement
    if (overlay.open) {
      this.originalLabelIds = this.selectedLabelIds()
    } else if (
      this.originalLabelIds.join() !== this.selectedLabelIds().join()
    ) {
      this.dispatchEvent(
        new CustomEvent('newLabelsSelected', {
          detail: { labelIds: this.selectedLabelIds() },
        }),
      )
    }
  }

  selectedLabelIds() {
    return this.labels
      .filter((label) => {
        return label.getAttribute('aria-checked') === 'true'
      })
      .map((label) => {
        return label.getAttribute('data-label-id')!
      })
  }

  submitLabels() {
    if (this.form) {
      this.form.submit()
    }
  }
}
