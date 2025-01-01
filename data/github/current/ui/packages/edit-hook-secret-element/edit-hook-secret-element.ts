import {controller, target} from '@github/catalyst'

@controller
export class EditHookSecretElement extends HTMLElement {
  @target declare view: HTMLElement
  // edit is initially a template to avoid a form submit with an empty value before this component is connected
  @target declare editTemplate: HTMLTemplateElement

  private editing = false
  private declare viewElement: HTMLElement
  private declare editElement: HTMLElement

  connectedCallback() {
    // store the target elements because they will be removed from the DOM
    this.viewElement = this.view
    this.editElement = this.editTemplate.content.firstElementChild?.cloneNode(true) as HTMLElement
  }

  toggleView() {
    const {editElement, viewElement} = this
    this.editing = !this.editing

    if (this.editing) {
      this.appendChild(editElement)
      viewElement.remove()
      editElement.querySelector('input')?.focus()
    } else {
      this.appendChild(viewElement)
      if (this.contains(editElement)) {
        // It's important that this be _removed_ to avoid an empty value in the form submission if not editing the secret
        this.removeChild(editElement)
      }
    }
  }
}
