import {controller, target} from '@github/catalyst'
import {requestSubmit} from '@github-ui/form-utils'

@controller
export class SecurityAnalysisDependabotUpdatesElement extends HTMLElement {
  @target declare onActionsEnableNewReposCheckbox: HTMLInputElement
  @target declare selfHostedEnableNewReposCheckbox: HTMLInputElement

  connectedCallback() {
    // Enforce that self-hosted runners can only be used if Dependabot on Actions is enabled
    if (this.onActionsEnableNewReposCheckbox && this.selfHostedEnableNewReposCheckbox) {
      // Prevent the self-hosted checkbox from being checked if Dependabot on Actions is disabled
      this.selfHostedEnableNewReposCheckbox.disabled = !this.onActionsEnableNewReposCheckbox.checked

      this.onActionsEnableNewReposCheckbox.addEventListener('change', () => {
        if (this.onActionsEnableNewReposCheckbox.checked) {
          this.selfHostedEnableNewReposCheckbox.disabled = false
        } else {
          this.selfHostedEnableNewReposCheckbox.checked = false

          if (this.selfHostedEnableNewReposCheckbox.form) {
            requestSubmit(this.selfHostedEnableNewReposCheckbox.form)
          }

          this.selfHostedEnableNewReposCheckbox.disabled = true
        }
      })
    }
  }
}
