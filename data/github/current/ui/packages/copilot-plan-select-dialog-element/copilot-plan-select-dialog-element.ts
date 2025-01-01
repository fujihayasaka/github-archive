import {controller, target} from '@github/catalyst'

@controller
export class CopilotPlanSelectDialogElement extends HTMLElement {
  @target declare submitBtn: HTMLButtonElement
  @target declare formEl: HTMLFormElement

  connectedCallback() {
    this.formEl.addEventListener('change', this.handleChange)
  }

  handleChange = () => {
    this.submitBtn.classList.remove('Button--inactive')
  }
}
