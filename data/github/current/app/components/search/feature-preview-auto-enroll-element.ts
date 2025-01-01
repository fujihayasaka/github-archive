import {controller, target} from '@github/catalyst'

@controller
class FeaturePreviewAutoEnrollElement extends HTMLElement {
  @target declare button: HTMLButtonElement
  connectedCallback() {
    this.button.click()
  }
}
