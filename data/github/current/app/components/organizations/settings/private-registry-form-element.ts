import {controller, target} from '@github/catalyst'
import {TemplateInstance} from '@github/template-parts'

@controller
class PrivateRegistryFormElement extends HTMLElement {
  @target declare secretField: HTMLElement
  @target declare secretTemplate: HTMLTemplateElement
  @target declare passwordTemplate: HTMLTemplateElement
  @target declare SecretFields: HTMLElement
  @target declare updateSecretMsg: HTMLElement

  changeSecretFields(event: Event) {
    const currentTarget = event.currentTarget as HTMLInputElement
    const dataType = currentTarget.getAttribute('data-value')

    if (dataType === 'username_and_password') {
      this.secretField.replaceChildren(new TemplateInstance(this.passwordTemplate, {}))
    } else {
      this.secretField.replaceChildren(new TemplateInstance(this.secretTemplate, {}))
    }
  }

  showSecretFields() {
    this.SecretFields.hidden = false
    this.updateSecretMsg.hidden = true
  }
}
