import {controller, target} from '@github/catalyst'
import {hasDirtyFields} from '@github-ui/has-interactions'

@controller
class PinOrganizationRepoElement extends HTMLElement {
  @target declare form: HTMLFormElement
  @target declare submitButton: HTMLButtonElement

  async formModified() {
    this.submitButton.disabled = !hasDirtyFields(this.form)
  }
}
