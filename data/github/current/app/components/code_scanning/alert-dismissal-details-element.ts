import {controller, target} from '@github/catalyst'

@controller
class AlertDismissalDetailsElement extends HTMLElement {
  @target declare footer: HTMLElement
  @target declare form: HTMLFormElement
  @target declare radiogroup: HTMLElement

  connectedCallback() {
    this.reset()

    const details = this.closest('details')
    details?.addEventListener('toggle', () => {
      if (details.open) {
        this.radiogroup?.scrollIntoView({behavior: 'smooth', block: 'center'})
      }
    })
  }

  reset() {
    this.footer.hidden = true
    this.form.reset()
  }

  show() {
    this.footer.hidden = false
  }
}
