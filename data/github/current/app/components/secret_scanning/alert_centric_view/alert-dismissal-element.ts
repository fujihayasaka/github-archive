import {controller, target} from '@github/catalyst'

@controller
class AlertDismissalElement extends HTMLElement {
  @target declare footer: HTMLElement
  @target declare form: HTMLFormElement

  connectedCallback() {
    this.hide()
  }

  hide() {
    this.form.reset()
    this.footer.hidden = true
  }

  show() {
    this.footer.hidden = false
  }
}
