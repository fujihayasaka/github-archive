import {controller, target} from '@github/catalyst'

@controller
export class CopilotPlanSelectDialogElement extends HTMLElement {
  @target submitBtn!: HTMLButtonElement
  @target formEl!: HTMLFormElement

  connectedCallback() {
    this.formEl.addEventListener('change', this.handleChange)
  }

  handleChange = () => {
    this.submitBtn.classList.remove('Button--inactive')
  }
}
