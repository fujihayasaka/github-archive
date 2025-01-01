import {controller, target} from '@github/catalyst'

@controller
export class DeployKeyPolicyWarningElement extends HTMLElement {
  @target disableWarningBanner: HTMLElement | undefined
  @target saveDeployKeyPolicyButton: HTMLButtonElement | undefined
  @target saveDeployKeyPolicyButtonAreYouSure: HTMLButtonElement | undefined

  // shows the warning banner and changes the save button
  // such that it's wrapped in a confirmation dialog
  showWarning() {
    if (this.disableWarningBanner) {
      this.disableWarningBanner.hidden = false
    }
    if (this.saveDeployKeyPolicyButton) {
      this.saveDeployKeyPolicyButton.hidden = true
    }
    if (this.saveDeployKeyPolicyButtonAreYouSure) {
      this.saveDeployKeyPolicyButtonAreYouSure.hidden = false
    }
  }

  // hides the warning banner and changes the save button
  // such that it's no longer wrapped in a confirmation dialog
  hideWarning() {
    if (this.disableWarningBanner) {
      this.disableWarningBanner.hidden = true
    }
    if (this.saveDeployKeyPolicyButton) {
      this.saveDeployKeyPolicyButton.hidden = false
    }
    if (this.saveDeployKeyPolicyButtonAreYouSure) {
      this.saveDeployKeyPolicyButtonAreYouSure.hidden = true
    }
  }
}
