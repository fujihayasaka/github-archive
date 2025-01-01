import {controller, target, targets} from '@github/catalyst'

@controller
export class ShareButtonFormSubmitHandlerElement extends HTMLElement {
  @target declare form: HTMLFormElement

  submit() {
    this.form.submit()
  }
}

@controller
export class ShareButtonTextHandlerElement extends HTMLElement {
  @targets declare text: HTMLInputElement[]
  @target declare share_text: HTMLInputElement | HTMLTextAreaElement

  updateText() {
    for (const element of this.text) {
      element.value = this.share_text.value
    }
  }
}
